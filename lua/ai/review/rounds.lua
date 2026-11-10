-- Review rounds: one round model for every conversation that can change the
-- worktree.
--
-- A round is a baseline (util.baseline, kind "round") plus the conversation
-- that owns it and the root it was taken in. Every source opens rounds through
-- submit(), so the rules below live in one place:
--
--   source        how it reaches submit()                        conversation
--   claude        UserPromptSubmit hook -> ai.review.hook         claude:<session_id>
--   codex         UserPromptSubmit hook -> ai.review.hook         codex:<session_id>
--   cc-acp/http   CodeCompanion's on_before_submit (this file)    cc:<nonce>:<chat.id>
--   manual        <leader>aV (start)                              the bound session, or none
--
-- A conversation's root is the Git toplevel of the agent's working directory,
-- fixed when the session starts: a native terminal's cwd at TermOpen, a chat's
-- cwd at ChatCreated (CodeCompanion's agents and tools work in getcwd()).
--
-- This module also keeps the registry delivery checks against (resolve_sink):
-- one native terminal per agent and one entry per CodeCompanion chat, in this
-- Nvim only. It is in memory and starts empty in every process; what survives a
-- restart is the round itself, in its ref, and the draft beside it.
--
-- `cc:` ids carry a nonce made once per process: chat.id comes from an unseeded
-- math.random, so two Nvims (or one Nvim before and after a restart) hand out
-- the same first id.
--
-- Loaded on first use only -- an agent terminal's TermOpen, a CodeCompanion
-- chat, a hook event or a review key (lua/ai/init.lua) -- and util.baseline
-- only once a snapshot is really taken.
local M = {}

local uv = vim.uv
local INFO, WARN = vim.log.levels.INFO, vim.log.levels.WARN

-- Same conversation submitting again this soon is the hook firing twice, not a
-- new prompt. A field rather than a local so the spec can shorten it.
M._DEDUPE_MS = 1000

-- Claude's SessionStart sources that change the terminal's foreground session.
-- `fork` is left out: /fork's background copy, /branch and a session moved to
-- the background all report it, and none of them is what the TUI now shows. A
-- fork that did become the foreground is corrected by its next prompt.
local FOREGROUND = { startup = true, resume = true, clear = true, compact = true }

-- The ai.review.config switch that gates each CodeCompanion source.
local GATES = { ["cc-acp"] = "codecompanion_acp", ["cc-http"] = "codecompanion_http" }

-- Subject words per source: "nvim review: Claude round 11:22:33".
local SOURCE_LABELS = {
  claude = "Claude",
  codex = "Codex",
  ["cc-acp"] = "Agent chat",
  ["cc-http"] = "API chat",
  manual = "Manual",
}

-- Formatted as integers: hrtime is a double, and once the machine has been up
-- for about 28 hours (1e14 ns) concatenation prints it as "1.01e+14", which
-- drops digits.
local NONCE = ("%d-%d"):format(uv.os_getpid(), uv.hrtime())

-- agent -> { agent, buf, root, session?, dirty, reported_at?, drift_noticed? }
local native = {}
-- conversation -> { conversation, chat, chat_id, bufnr, kind, root }
local chats = {}
-- conversation key -> { turn?, at } of its last accepted submit
local submitted = {}
-- conversation key -> { tree, root, id?, sha?, time?, pending? }: the newest
-- round this process opened for it
local last_round = {}
-- root -> the newest round entry this process opened there
local newest_here = {}
-- native conversation -> wall-clock seconds (with the fraction) of its newest
-- prompt this process heard of
local prompted = {}

local function settings()
  return require("ai.review.config").get()
end

-- The snacks notifier cuts a line off at its width.max (0.4 x 'columns', 62
-- cells of text at 160) instead of wrapping it, and what to do next sits at
-- the end of a sentence. So a notice is a list of short lines, a clause each,
-- with a long path or git's own words on a line of their own. A vim.ui.select
-- prompt is the snacks picker's one-line title, so it stays one short line and
-- the reason goes into a notice beside it. tests/review_round_spec.lua pins
-- both lengths.
---@param lines string|string[]
---@param level? integer
local function notify(lines, level)
  local msg = type(lines) == "table" and table.concat(lines, "\n") or lines
  vim.notify(msg, level or WARN, { title = "AI review" })
end

local function now_ms()
  return uv.hrtime() / 1e6
end

local function short(id)
  id = tostring(id or "")
  return #id > 8 and id:sub(1, 8) .. "…" or id
end

local function tilde(path)
  return vim.fn.fnamemodify(path, ":~")
end

local function agent_label(agent)
  local p = require("ai.config").providers[agent]
  return p and p.label or agent
end

---The nonce this process puts into its `cc:` conversation ids.
---@return string
function M.nonce()
  return NONCE
end

---The Git toplevel that contains `path` (a file or directory; default: the
---cwd), realpath'd -- or, outside any repository, the directory itself. Runs no
---git: the nearest ancestor holding a `.git` (directory or file) is the
---worktree's top, linked worktrees and submodules included.
---@param path? string
---@return string
function M.toplevel(path)
  local abs = vim.fs.abspath((path and path ~= "") and path or (uv.cwd() or vim.fn.getcwd()))
  local st = uv.fs_stat(abs)
  local dir = (st and st.type == "directory") and abs or vim.fs.dirname(abs)
  local top = vim.fs.root(dir, ".git") or dir
  return uv.fs_realpath(top) or top
end

---Where the feedback draft of round `id` in `root` lives ("unowned" for the
---root's draft that belongs to no round):
---stdpath("state")/ai-review/<sha256(realpath(root)):sub(1,12)>/<id>.md.
---Shared by every Nvim, which is what lets retention spare a round another
---process is still writing feedback for.
---@param root string
---@param id string
---@return string
function M.draft_path(root, id)
  local real = uv.fs_realpath(root) or root
  return ("%s/ai-review/%s/%s.md"):format(vim.fn.stdpath("state"), vim.fn.sha256(real):sub(1, 12), id)
end

---The retention exemption util.baseline consults before pruning: a round
---whose draft is a non-empty file is kept.
---@param entry baseline.Entry
---@return boolean
function M._exempt(entry)
  if type(entry) ~= "table" or entry.kind ~= "round" or not entry.root or not entry.id then return false end
  local st = uv.fs_stat(M.draft_path(entry.root, entry.id))
  return st ~= nil and st.type == "file" and st.size > 0
end

-- save() prunes on its own, so the predicate has to be in place before the
-- first round is saved. Keyed on the module table, so a reloaded
-- util.baseline is given it again.
local exempt_installed_on
local function baseline()
  local mod = require("util.baseline")
  if exempt_installed_on ~= mod then
    mod.set_exempt(M._exempt)
    exempt_installed_on = mod
  end
  return mod
end

---The word a round's Source trailer stands for ("claude" -> "Claude"), nil
---for none.
---@param source? string
---@return string|nil
function M.source_label(source)
  if type(source) ~= "string" or source == "" then return nil end
  return SOURCE_LABELS[source] or source
end

---When this process last heard native `conversation` submit a prompt, in
---seconds since the epoch with the fraction kept (turn ends in the agents'
---records have milliseconds); nil if it never did. A prompt that kept the
---round before it (nothing changed since) opens no round, so this is how
---ai.review.labels tells that round's session is busy again.
---@param conversation? string
---@return number|nil
function M.prompted_at(conversation)
  return conversation and prompted[conversation] or nil
end


---The tab variables of a review view (vim.t.ai_review) for a round entry from
---util.baseline.list, or nil for any other entry. The vcs layer gets a round's
---metadata here instead of parsing trailers itself.
---@param entry? baseline.Entry
---@return { id: string, sha: string, conversation?: string, source?: string, root: string, late: boolean }|nil
function M.review_vars(entry)
  if type(entry) ~= "table" or entry.kind ~= "round" or not entry.id or not entry.sha then return nil end
  local trailers = type(entry.trailers) == "table" and entry.trailers or {}
  return {
    id = entry.id,
    sha = entry.sha,
    conversation = trailers.Conversation,
    source = trailers.Source,
    root = entry.root or trailers.Root,
    late = trailers.Late == "1",
  }
end

---------------------------------------------------------------------------
-- The registry
---------------------------------------------------------------------------

local function terminal_running(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) or vim.bo[buf].buftype ~= "terminal" then return false end
  local chan = vim.bo[buf].channel
  return chan ~= nil and chan > 0 and vim.fn.jobwait({ chan }, 0)[1] == -1
end

local function native_conversation(entry)
  return entry.session and (entry.agent .. ":" .. entry.session) or nil
end

---Whether native `conversation` is the session an agent terminal of this Nvim
---is running now.
---@param conversation? string
---@return boolean
function M.running(conversation)
  if not conversation then return false end
  for _, entry in pairs(native) do
    if native_conversation(entry) == conversation and terminal_running(entry.buf) then return true end
  end
  return false
end

local function chat_alive(entry)
  local chat = entry and entry.chat
  if not (chat and vim.api.nvim_buf_is_valid(entry.bufnr)) then return nil end
  return chat.id == entry.chat_id and chat or nil
end

-- Typed input that marks a terminal "may have changed conversation". Called
-- for every key Nvim reads, so the common case returns at once.
local function on_key(_, typed)
  if next(native) == nil or not typed or typed == "" then return end
  if vim.api.nvim_get_mode().mode ~= "t" then return end
  local buf = vim.api.nvim_get_current_buf()
  local entry
  for _, e in pairs(native) do
    if e.buf == buf then entry = e end
  end
  if not entry or entry.dirty then return end
  local keys = vim.fn.keytrans(typed)
  -- The wheel and clicks scroll or focus; they do not talk to the agent.
  if keys:find("Mouse", 1, true) or keys:find("ScrollWheel", 1, true) or keys:find("Drag", 1, true)
    or keys:find("Release", 1, true) or keys:find("^<Focus") then
    return
  end
  -- Nor do this config's own Terminal-mode keys (jk, <C-\>, <C-h/j/k/l>, ...),
  -- or leaving the panel to review would mark every round's terminal dirty.
  if vim.fn.mapcheck(keys, "t") ~= "" then return end
  entry.dirty = true
end
M._on_key = on_key

local key_ns
local function watch_keys()
  if key_ns then return end
  key_ns = vim.api.nvim_create_namespace("ai.review.rounds.keys")
  -- Runs on every key: a failure here must stay silent rather than report
  -- itself on each keystroke. The worst it costs is a missed "dirty".
  vim.on_key(function(key, typed) pcall(on_key, key, typed) end, key_ns)
end

local group = vim.api.nvim_create_augroup("ai_review_rounds", { clear = true })

---Register a native agent terminal: its agent, and its root, fixed now. Called
---(scheduled) on every TermOpen by lua/ai/init.lua; anything that is not an
---agent terminal is ignored. One terminal per agent: a newer one replaces the
---entry. `cwd` is the directory the job started in when Snacks recorded none.
---@param buf integer
---@param cwd? string
---@return table|nil entry
function M.track_terminal(buf, cwd)
  local agent = require("util.terminal").agent_of(buf)
  if not agent then return nil end
  local current = native[agent]
  if current and current.buf == buf then return current end
  local info = vim.b[buf].snacks_terminal or {}
  local entry = {
    agent = agent,
    buf = buf,
    root = M.toplevel(info.cwd or cwd),
    dirty = false,
  }
  native[agent] = entry
  watch_keys()
  vim.api.nvim_create_autocmd({ "TermClose", "BufWipeout" }, {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      if native[agent] == entry then native[agent] = nil end
    end,
  })
  return entry
end

-- A hook event for an agent whose TermOpen went unseen (a terminal started
-- before this module could hear of it): find its panel now.
local function native_entry(agent)
  local entry = native[agent]
  if entry and terminal_running(entry.buf) then return entry end
  local found
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if terminal_running(buf) and require("util.terminal").agent_of(buf) == agent then found = buf end
  end
  return found and M.track_terminal(found) or entry
end

local function report_session(entry, session)
  entry.session = session
  entry.dirty = false
  entry.reported_at = os.time()
end

---Register a CodeCompanion chat and, while its source is on, hook its
---on_before_submit. The callback runs on a user submit or a regenerate only,
---never an auto_submit (a tool loop's next step), and before the request
---leaves: it takes the round's snapshot and waits for it, bounded by
---hook_wait_ms, so the baseline lands before the agent's first write.
---@param chat table a CodeCompanion.Chat (or anything shaped like one)
---@return table|nil entry
function M.attach_chat(chat)
  if type(chat) ~= "table" or chat.id == nil or not chat.bufnr then return nil end
  local kind = (chat.adapter and chat.adapter.type == "acp") and "cc-acp" or "cc-http"
  local conversation = ("cc:%s:%s"):format(NONCE, tostring(chat.id))
  local existing = chats[conversation]
  if existing and existing.chat == chat then return existing end
  local entry = {
    conversation = conversation,
    chat = chat,
    chat_id = chat.id,
    bufnr = chat.bufnr,
    kind = kind,
    root = M.toplevel(vim.fn.getcwd()),
  }
  chats[conversation] = entry
  -- A source switched off adds no callback; one switched off later is read
  -- again on every submit.
  if settings().sources[GATES[kind]] and type(chat.add_callback) == "function" then
    chat:add_callback("on_before_submit", function()
      -- Never return false: that would cancel the user's submit.
      local ok, err = pcall(M._before_submit, conversation)
      if not ok then notify({ "Review round for a chat failed:", tostring(err) }) end
    end)
  end
  return entry
end

---The on_before_submit body, exposed for the spec.
---@param conversation string
function M._before_submit(conversation)
  local entry = chats[conversation]
  if not entry then return end
  local cfg = settings()
  if not cfg.sources[GATES[entry.kind]] then return end
  local landed, expired = false, false
  M.submit({
    source = entry.kind,
    conversation = conversation,
    root = entry.root,
    done = function() landed = true end,
    gave_up = function() return expired end,
  })
  if not landed and cfg.hook_wait_ms > 0 then
    vim.wait(cfg.hook_wait_ms, function() return landed end, 10)
  end
  -- From here on a baseline that still lands is Late: the request is about to
  -- leave without it.
  expired = not landed
end

---`User CodeCompanionChatCreated`: find the chat and attach it. Fires only
---from a loaded CodeCompanion, so nothing is loaded to answer.
---@param data? { bufnr?: integer, id?: integer }
function M.chat_created(data)
  local cc = package.loaded["codecompanion"]
  if type(cc) ~= "table" or type(data) ~= "table" or not data.bufnr then return end
  local ok, chat = pcall(cc.buf_get_chat, data.bufnr)
  if ok and type(chat) == "table" and chat.id ~= nil then M.attach_chat(chat) end
end

---`User CodeCompanionChatClosed`: forget that chat. Its rounds keep their
---owner; delivering to it is refused from now on.
---@param data? { bufnr?: integer, id?: integer }
function M.chat_closed(data)
  if type(data) ~= "table" then return end
  for conversation, entry in pairs(chats) do
    if entry.bufnr == data.bufnr and (data.id == nil or entry.chat_id == data.id) then
      chats[conversation] = nil
    end
  end
end

---The conversation a buffer belongs to: an agent terminal's current session,
---or a chat's id. `bound` is true for such a buffer even while its terminal has
---not reported a session (then `conversation` is nil).
---@param buf? integer
---@return string|nil conversation, string|nil root, boolean bound
function M.conversation_of(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  for _, entry in pairs(native) do
    if entry.buf == buf and terminal_running(buf) then return native_conversation(entry), entry.root, true end
  end
  for conversation, entry in pairs(chats) do
    if entry.bufnr == buf and chat_alive(entry) then return conversation, entry.root, true end
  end
  return nil, nil, false
end

---The conversation of the chat on the right (ai.slot.shown_here: the one
---shown in this tabpage, or, from a CodeDiff view, in the page it came from)
---as this registry knows it, with its root and buffer. Nil when nothing is
---on the right, only a question could tell which, or what is there is no
---conversation here (a terminal that has not reported its session).
---@return string|nil conversation, string|nil root, integer|nil buf
local function on_the_right()
  local ok, buf = pcall(function()
    local slot = require("ai.slot")
    local item = slot.shown_here()
    return item and slot.buf_of(item)
  end)
  if not (ok and type(buf) == "number") then return nil end
  local conversation, root = M.conversation_of(buf)
  return conversation, root, buf
end

local function chat_label(entry)
  local adapter = entry.chat.adapter or {}
  local name = adapter.formatted_name or adapter.name or "?"
  if entry.kind == "cc-acp" then return ("Agent chat · %s (ACP) #%d"):format(name, entry.bufnr) end
  return ("API chat · %s (HTTP) #%d"):format(name, entry.bufnr)
end

local function native_label(entry)
  local what = entry.session and ("session " .. short(entry.session)) or "session not reported yet"
  return ("%s · %s"):format(agent_label(entry.agent), what)
end

---Human name of a conversation id, for notifications and pickers.
---@param conversation? string
---@return string
function M.label(conversation)
  if not conversation then return "no conversation" end
  local agent, session = conversation:match("^(%l+):(.+)$")
  if (agent == "claude" or agent == "codex") then
    return ("%s session %s"):format(agent_label(agent), short(session))
  end
  local entry = chats[conversation]
  if entry and chat_alive(entry) then return chat_label(entry) end
  local nonce, id = conversation:match("^cc:([^:]+):(.+)$")
  if nonce then
    return ("CodeCompanion chat %s (%s)"):format(id, nonce == NONCE and "closed" or "an earlier Nvim")
  end
  return conversation
end

---The live sessions in `root` this Nvim could deliver to: running agent
---terminals and open chats, the chat on the right first.
---@param root string
---@return { kind: "native"|"cc", conversation?: string, agent?: string, chat?: table, buf: integer, root: string, label: string, session_known?: boolean, dirty?: boolean }[]
function M.live_conversations(root)
  root = uv.fs_realpath(root) or root
  local out = {}
  local agents = vim.tbl_keys(native)
  table.sort(agents)
  for _, agent in ipairs(agents) do
    local entry = native[agent]
    if entry.root == root and terminal_running(entry.buf) then
      out[#out + 1] = {
        kind = "native",
        agent = agent,
        conversation = native_conversation(entry),
        buf = entry.buf,
        root = entry.root,
        label = native_label(entry),
        session_known = entry.session ~= nil,
        dirty = entry.dirty,
      }
    end
  end
  local cc = vim.tbl_values(chats)
  table.sort(cc, function(a, b) return a.bufnr < b.bufnr end)
  for _, entry in ipairs(cc) do
    local chat = chat_alive(entry)
    if chat and entry.root == root then
      out[#out + 1] = {
        kind = "cc",
        conversation = entry.conversation,
        chat = chat,
        buf = entry.bufnr,
        root = entry.root,
        label = chat_label(entry),
      }
    end
  end
  local _, _, right = on_the_right()
  for i, item in ipairs(out) do
    if item.buf == right then
      table.insert(out, 1, table.remove(out, i))
      break
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Opening rounds
---------------------------------------------------------------------------

---@class ai.review.SubmitEvent
---@field source "claude"|"codex"|"cc-acp"|"cc-http"|"manual"
---@field conversation? string the owner (§1.2 id); manual may have none
---@field root string the conversation's root
---@field turn? string Codex turn_id: a steer repeats its turn
---@field gave_up? fun(): boolean has the source stopped waiting? (Late)
---@field done? fun() called once the tree is written, or the submit is dropped
---@field force? boolean <leader>aV: no dedupe
---@field on_round? fun(round: table, reused: boolean) the round opened or kept

local function once(fn)
  local called = false
  return function()
    if called then return end
    called = true
    if fn then fn() end
  end
end

local function run_submit(ev, done)
  local base = require("util.baseline")
  local loc, err = base.locate(ev.root)
  if not loc then
    -- Rule 1: outside Git the registry is updated (the caller did) and that
    -- is all.
    if ev.source == "manual" then notify({ "Review rounds need a Git worktree:", tostring(err) }) end
    return done()
  end
  local root = loc.toplevel
  local key = ev.conversation or ("unowned:" .. root)

  -- Rule 2: a Codex steer repeats its turn; a hook that fired twice repeats
  -- itself within a second.
  if ev.conversation and not ev.force then
    local last = submitted[key]
    local now = now_ms()
    if last and ((ev.turn ~= nil and last.turn == ev.turn) or now - last.at < M._DEDUPE_MS) then
      return done()
    end
    submitted[key] = { turn = ev.turn, at = now }
  end

  -- Rule 3: the snapshot goes first in line, and the source is released as
  -- soon as its tree exists -- the commit and the ref are not worth waiting for.
  local function landed(tree, info)
    local late = ev.gave_up ~= nil and ev.gave_up() == true
    done()
    if not tree then
      return notify({
        ("No review baseline for this %s prompt:"):format(SOURCE_LABELS[ev.source] or ev.source),
        tostring(info),
      })
    end
    -- Rule 4: nothing changed since this conversation's last round here.
    local prev = last_round[key]
    if prev and prev.root == root and prev.tree == tree then
      if ev.on_round then ev.on_round(prev, true) end
      return
    end
    -- Rule 5: a new round. Claimed before the save, so a second submit with
    -- the same tree while this one is in flight keeps it instead of saving a
    -- twin.
    local claim = { tree = tree, root = root, pending = true }
    last_round[key] = claim
    baseline().save(root, "round", {
      tree = tree,
      subject = ("nvim review: %s round %s"):format(SOURCE_LABELS[ev.source] or ev.source, os.date("%H:%M:%S")),
      Source = ev.source,
      Conversation = ev.conversation,
      Root = root,
      Late = late or nil,
    }, function(entry, save_err)
      if not entry then
        if last_round[key] == claim then last_round[key] = nil end
        return notify({ "Could not save the review round:", tostring(save_err) })
      end
      local round = { tree = tree, root = root, id = entry.id, sha = entry.sha, time = entry.time,
        conversation = ev.conversation, source = ev.source, late = late }
      if last_round[key] == claim then last_round[key] = round end
      newest_here[root] = round
      if ev.on_round then ev.on_round(round, false) end
    end)
  end
  base.snapshot(root, function(tree, info)
    local ok, cb_err = pcall(landed, tree, info)
    if not ok then
      done()
      notify({ "Review round failed:", tostring(cb_err) })
    end
  end, { priority = true })
end

---Open a round for a prompt (or <leader>aV). The single place the round rules
---apply:
---
---  1. a root outside Git opens nothing;
---  2. the same conversation's same Codex turn, or a repeat within a second,
---     opens nothing;
---  3. the snapshot runs first in its queue; `done` fires once its tree is
---     written, and the round is Late when `gave_up()` says the source had
---     stopped waiting by then;
---  4. a tree equal to the conversation's last round in this process keeps
---     that round;
---  5. otherwise a round is saved with Source/Conversation/Root/Late trailers,
---     and retention runs (rounds with a draft are exempt).
---
---`done` is always called, exactly once, also when the submit is dropped.
---@param ev ai.review.SubmitEvent
function M.submit(ev)
  local done = once(ev.done)
  local ok, err = pcall(run_submit, ev, done)
  if not ok then
    done()
    notify({ "Review round failed:", tostring(err) })
  end
end

---Whether a Claude prompt is Claude going on with the user's work rather than
---a request: it is woken when a background task it started (a Bash command,
---a workflow) finishes -- "<task-notification>" -- or when a background agent
---it started hands its result back, as "<agent-message ...>\n[Subagent
---hand-back]", alone when queued during a turn or framed by "Another Claude
---session sent a message...:" when Claude was idle. Another session's message,
---or an agent's that is not a hand-back, is a request of its own. Both fire
---UserPromptSubmit like a prompt typed by the user.
---@param prompt any
---@return boolean
local function continues_turn(prompt)
  if type(prompt) ~= "string" then return false end
  if prompt:match("^%s*<task%-notification>") then return true end
  local body = prompt:gsub("^%s*Another Claude session sent a message[^\n]*:[ \t]*\n", "", 1)
  return body:match("^%s*<agent%-message[^>]*>%s*%[Subagent hand%-back%]") ~= nil
end
M._continues_turn = continues_turn

---A native hook event, handed over by ai.review.hook (which has already
---dropped subagent events, disabled sources and missed submits, and released
---session events). A submit reports the session and opens a round -- except
---Claude waking itself to go on with the work (continues_turn), which only
---marks the session prompted; Claude's SessionStart only reports the session,
---for the sources that change the foreground one.
---@param ev ai.review.NativeEvent
function M.native_event(ev)
  local release = once(ev.done)
  local payload = type(ev.payload) == "table" and ev.payload or {}
  -- ai.review.hook drops these already; a second guard costs nothing.
  if payload.agent_id ~= nil then return release() end
  local agent = ev.agent
  local entry = native_entry(agent)
  local session = type(payload.session_id) == "string" and payload.session_id ~= "" and payload.session_id or nil

  if ev.event == "session" then
    if entry and session and FOREGROUND[payload.source] then report_session(entry, session) end
    return release()
  end

  if entry and session then report_session(entry, session) end
  if session then
    local sec, usec = uv.gettimeofday()
    prompted[agent .. ":" .. session] = sec + usec / 1e6
  end
  -- Claude waking itself to go on with the work opens no round (continues_turn):
  -- what it changes, and where that work ends, belong to the session's newest
  -- round. But the session is at work again.
  if agent == "claude" and continues_turn(payload.prompt) then return release() end
  local root = entry and entry.root or M.toplevel(payload.cwd)
  -- Claude's Bash can `cd` into another repository; the session's root stays
  -- the one it started in, and saying so once is enough.
  if entry and type(payload.cwd) == "string" and payload.cwd ~= "" and not entry.drift_noticed then
    local here = M.toplevel(payload.cwd)
    if here ~= entry.root then
      entry.drift_noticed = true
      notify({
        ("%s is working outside its root now:"):format(agent_label(agent)),
        tilde(here),
        "Its review rounds are still recorded for:",
        tilde(entry.root),
      }, INFO)
    end
  end
  M.submit({
    source = agent,
    conversation = session and (agent .. ":" .. session) or nil,
    root = root,
    turn = agent == "codex" and type(payload.turn_id) == "string" and payload.turn_id or nil,
    done = release,
    gave_up = ev.gave_up,
  })
end

---<leader>aV: open a round now. Its owner is the session the current buffer
---belongs to (an agent terminal or a chat; a terminal that has not reported
---its session gives none), else the chat on the right when it works in this
---root and is a known conversation, else nobody -- delivery then asks.
---@param opts? { buf?: integer }
function M.start(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local owner, root, bound = M.conversation_of(buf)
  if not bound then
    local name = vim.api.nvim_buf_get_name(buf)
    local file = vim.bo[buf].buftype == "" and name ~= "" and not name:match("^%a[%w+.-]*://") and name or nil
    root = M.toplevel(file)
    local right, right_root = on_the_right()
    if right and right_root == root then owner = right end
  end
  M.submit({
    source = "manual",
    conversation = owner,
    root = root,
    force = true,
    on_round = function(round, reused)
      local when = os.date("%H:%M:%S", round.time or os.time())
      local whose = owner and ("Conversation: " .. M.label(owner))
        or "No conversation yet: delivering feedback asks where it goes"
      if reused then
        notify({ ("Round %s is already the current state."):format(when), whose }, INFO)
      else
        notify({ ("Review round %s started"):format(when), "Root: " .. tilde(root), whose }, INFO)
      end
    end,
  })
end

---Which round <leader>av shows for `root`: the newest round of the current
---buffer's conversation, else of the chat on the right's, else the newest
---this process opened in `root`, else the newest there at all.
---`cb(entry, why)` with why "buffer"|"right"|"process"|"latest", or
---`cb(nil, err?)` when there is none.
---@param root string
---@param cb fun(entry: baseline.Entry|nil, why_or_err?: string)
---@param opts? { buf?: integer }
function M.select_round(root, cb, opts)
  opts = opts or {}
  local wants = {}
  local own = M.conversation_of(opts.buf)
  if own then wants[#wants + 1] = { conversation = own, why = "buffer" } end
  local right = on_the_right()
  if right and right ~= own then wants[#wants + 1] = { conversation = right, why = "right" } end
  require("util.baseline").list(root, "round", function(entries, err)
    if err then return cb(nil, err) end
    for _, want in ipairs(wants) do
      for _, e in ipairs(entries) do
        if e.trailers.Conversation == want.conversation then return cb(e, want.why) end
      end
    end
    local mine = newest_here[entries[1] and entries[1].root or (uv.fs_realpath(root) or root)]
    if mine then
      for _, e in ipairs(entries) do
        if e.id == mine.id then return cb(e, "process") end
      end
    end
    if entries[1] then return cb(entries[1], "latest") end
    cb(nil)
  end)
end

---------------------------------------------------------------------------
-- Delivery checks (D4)
---------------------------------------------------------------------------

local function busy(chat)
  local companion = require("ai.companion")
  if type(companion.busy) == "function" then
    local ok, res = pcall(companion.busy, chat)
    if ok then return res == true end
  end
  -- A turn's tool loop clears current_request and makes the buffer editable
  -- between steps; only _turn_in_progress stays set throughout.
  local ok, res = pcall(function()
    return chat.current_request ~= nil or chat._turn_in_progress == true or not vim.bo[chat.bufnr].modifiable
  end)
  return not ok or res
end

local function confirm(prompt, yes, cb)
  vim.ui.select({ yes, "Cancel (keep the draft)" }, { prompt = prompt, kind = "ai_review_confirm" }, function(choice)
    cb(choice == yes)
  end)
end

local function target_of(item, owner, redirected)
  return {
    kind = item.kind,
    conversation = item.conversation,
    agent = item.agent,
    chat = item.chat,
    buf = item.buf,
    root = item.root,
    label = item.label,
    owner = owner,
    redirected = redirected == true,
  }
end

-- Rule 3, also for a target chosen in a picker.
local function deliverable(target, cb)
  if target.kind == "cc" and busy(target.chat) then
    notify({ "The chat is replying.", "Draft kept: deliver again once it is done." })
    return cb(nil, "busy")
  end
  cb(target)
end

-- Pick one of the live sessions in `root`. The pick itself is the explicit
-- choice; `confirm_with` adds the one confirmation a redirect needs, as the
-- prompt and the choice that says yes.
local function pick(root, owner, confirm_with, cb)
  local items = M.live_conversations(root)
  if #items == 0 then
    notify({
      "No session to deliver to.",
      "Root: " .. tilde(root),
      "Start Claude/Codex or open a chat there. Draft kept.",
    })
    return cb(nil, "no-session")
  end
  vim.ui.select(items, {
    prompt = "Deliver review feedback to",
    kind = "ai_review_target",
    format_item = function(item) return item.label end,
  }, function(item)
    if not item then return cb(nil, "cancelled") end
    local target = target_of(item, owner, confirm_with ~= nil)
    if not confirm_with then return deliverable(target, cb) end
    local prompt, yes_choice = confirm_with(target)
    confirm(prompt, yes_choice, function(yes)
      if not yes then return cb(nil, "cancelled") end
      deliverable(target, cb)
    end)
  end)
end

-- Rule 4: the owner is gone. Refuse, and -- unless redirect is off -- offer the
-- current sessions of the same root, with one confirmation naming both. The
-- notice's first line says what happened in one short sentence, so it also
-- heads the offer.
---@param lines string[]
local function owner_gone(lines, owner, root, cb)
  notify(lines)
  if not settings().redirect then return cb(nil, "owner-gone") end
  local offer = "Send to a current session…"
  vim.ui.select({ offer, "Keep the draft" }, { prompt = lines[1], kind = "ai_review_redirect" }, function(choice)
    if choice ~= offer then return cb(nil, "owner-gone") end
    pick(root, owner, function(target)
      return ("This round belongs to %s"):format(M.label(owner)), ("Send to %s"):format(target.label)
    end, cb)
  end)
end

local function refuse_root(there, here, cb)
  notify({
    "Refused: the target session is in another root.",
    "Session in: " .. tilde(there),
    "Round taken in: " .. tilde(here),
    "Draft kept.",
  })
  cb(nil, "root")
end

local function resolve_native(agent, session, owner, root, cb)
  local cfg = settings()
  local entry = native[agent]
  local label = agent_label(agent)
  if not (entry and terminal_running(entry.buf)) then
    local how = agent == "codex" and {
      "Draft kept: resume it with <leader>ar (codex resume).",
      "Codex reports its session only at your first prompt;",
      "until then, delivering asks you to confirm.",
    } or {
      ("Draft kept: resume session %s with <leader>ar,"):format(short(session)),
      "then deliver again.",
    }
    return owner_gone({ ("%s is not running in this Nvim."):format(label), unpack(how) }, owner, root, cb)
  end
  -- Rule 1 is about the owner's root, so first ask whether this terminal is
  -- the owner at all. One in another root that runs some other session, or
  -- has not reported one, is the owner gone (rule 4): the redirect lists this
  -- root's sessions only, so it cannot bypass rule 1. Only the owner's own
  -- session running elsewhere is a root refusal.
  if entry.root ~= root then
    if entry.session == session then return refuse_root(entry.root, root, cb) end
    return owner_gone({
      ("%s runs in another root now:"):format(label),
      tilde(entry.root),
      entry.session and ("It is in session %s there."):format(short(entry.session))
        or "It has not reported its session there.",
      ("This round belongs to session %s, taken in:"):format(short(session)),
      tilde(root),
      "Draft kept: quit it, resume that session with <leader>ar",
      "from a file in the round's root, then deliver again.",
    }, owner, root, cb)
  end

  local item = {
    kind = "native", agent = agent, conversation = owner, buf = entry.buf, root = entry.root,
    label = native_label(entry),
  }
  -- `doubt` explains, in a notice; `ask` is the one-line question.
  local doubt, ask
  if entry.session == nil then
    doubt = {
      agent == "codex" and "Codex reports its session only at your first prompt,"
        or ("%s has not reported its session,"):format(label),
      "so this delivery cannot be checked against",
      "the round's conversation.",
    }
    ask = ("%s has not reported its session yet. Deliver anyway?"):format(label)
  elseif entry.session ~= session then
    return owner_gone({
      ("%s is in another session now."):format(label),
      ("It runs session %s;"):format(short(entry.session)),
      ("this round belongs to session %s."):format(short(session)),
      "Draft kept: /resume it in the TUI to deliver there.",
    }, owner, root, cb)
  elseif entry.dirty then
    doubt = {
      ("You have typed in the %s terminal"):format(label),
      ("since it last reported session %s."):format(short(session)),
      "If that was /new, /resume or /fork,",
      "this feedback goes to another conversation.",
    }
    ask = ("%s may be in another conversation. Deliver anyway?"):format(label)
  end
  if doubt then
    if cfg.unknown_session == "refuse" then
      doubt[#doubt + 1] = 'Refused (unknown_session = "refuse"). Draft kept.'
      notify(doubt)
      return cb(nil, "unknown-session")
    end
    notify(doubt)
    return confirm(ask, "Deliver", function(yes)
      if yes then return cb(target_of(item, owner)) end
      cb(nil, "cancelled")
    end)
  end
  if vim.tbl_contains(cfg.always_confirm, agent) then
    return confirm(("Deliver to %s?"):format(M.label(owner)), "Deliver", function(yes)
      if yes then return cb(target_of(item, owner)) end
      cb(nil, "cancelled")
    end)
  end
  -- Rule 3 cannot be judged for a TUI; the seed's TTL covers a busy one.
  cb(target_of(item, owner))
end

local function resolve_chat(nonce, owner, root, cb)
  local entry = nonce == NONCE and chats[owner] or nil
  local chat = chat_alive(entry)
  if not chat then
    return owner_gone({ "That chat is closed or belongs to an earlier Nvim.", "Draft kept." }, owner, root, cb)
  end
  if entry.root ~= root then return refuse_root(entry.root, root, cb) end
  deliverable(target_of({
    kind = "cc", conversation = owner, chat = chat, buf = entry.bufnr, root = entry.root, label = chat_label(entry),
  }, owner), cb)
end

---@class ai.review.Target
---@field kind "native"|"cc"
---@field conversation? string the session delivered to (nil: a terminal that has not reported one)
---@field agent? "claude"|"codex" native targets: the provider to feed
---@field chat? table cc targets: the CodeCompanion chat
---@field buf integer the terminal or chat buffer
---@field root string
---@field label string
---@field owner? string the round's owner, when there was one
---@field redirected boolean delivered somewhere other than the owner

---Where feedback for a round owned by `conversation` (nil: no owner) in `root`
---may go, checked in order -- any failure refuses, warns (title "AI review")
---and keeps the draft:
---
---  1. root: `root` (a path, or a list of paths that must agree, e.g. the
---     view's and the draft header's) and the target session's root are one
---     realpath. Nothing bypasses this, and it asks nothing.
---  2. conversation: a native owner's terminal runs that session, unchanged
---     since it said so -- typed into, or not reported yet, asks first (or
---     refuses, unknown_session = "refuse"); always_confirm asks every time. A
---     chat owner is an open chat of this process.
---  3. not busy: a chat in mid-turn is refused.
---  4. an owner that is gone is refused, with an offer (redirect = true) to
---     pick a current session of the same root and confirm the change once.
---     A native owner is gone when its agent is not running, or runs another
---     session -- also from another root, where a terminal that has not
---     reported its session counts as another one; rule 1 refuses only the
---     owner's own session in another root.
---
---With no owner the same-root picker opens at once. `cb(target)` or
---`cb(nil, reason)`; asynchronous whenever anything is asked.
---@param conversation? string
---@param root string|string[]
---@param cb fun(target: ai.review.Target|nil, reason?: string)
function M.resolve_sink(conversation, root, cb)
  cb = cb or function() end
  local roots = type(root) == "table" and root or { root }
  local real
  for _, r in ipairs(roots) do
    local this = uv.fs_realpath(r) or r
    if real and this ~= real then
      notify({
        "Refused: this feedback was written for another root.",
        "Written for: " .. tilde(real),
        "Here: " .. tilde(this),
        "Draft kept.",
      })
      return cb(nil, "root")
    end
    real = this
  end
  if not real then return cb(nil, "root") end

  if conversation == nil or conversation == "" then return pick(real, nil, nil, cb) end
  local agent, session = conversation:match("^(%l+):(.+)$")
  if agent == "claude" or agent == "codex" then return resolve_native(agent, session, conversation, real, cb) end
  local nonce = conversation:match("^cc:([^:]+):.+$")
  if nonce then return resolve_chat(nonce, conversation, real, cb) end
  notify({ ("Unknown review conversation %q."):format(conversation), "Refused. Draft kept." })
  cb(nil, "unknown")
end

---------------------------------------------------------------------------
-- For the spec
---------------------------------------------------------------------------

---The registry and the per-process round memory, live.
function M._state()
  return {
    native = native, chats = chats, submitted = submitted, last_round = last_round, newest_here = newest_here,
    prompted = prompted,
  }
end

---Forget everything this process knows: registry and round memory.
function M._reset()
  for _, t in ipairs({ native, chats, submitted, last_round, newest_here, prompted }) do
    for k in pairs(t) do t[k] = nil end
  end
end

return M
