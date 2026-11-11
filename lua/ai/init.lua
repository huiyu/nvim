local M = {}

local config = require("ai.config")
local did_setup = false

---@param name string a provider
local function backend(name)
  return require("ai.backend." .. name)
end

local function label_of(name)
  local agent = config.agents[name]
  return agent and agent.label or tostring(name)
end

--- Run `fn` for `method` and turn a failure into a notification: the facade
--- is reached from mappings, where an escaped error is a traceback.
---@param label string the agent the failure is reported against
local function guard(label, method, fn, ...)
  local args = { ... }
  local ok, result = xpcall(function() return fn(unpack(args)) end, debug.traceback)
  if not ok then
    vim.notify(("%s %s failed:\n%s"):format(label, method, result), vim.log.levels.ERROR)
    return
  end
  return result
end

local function slot() return require("ai.slot") end
local function companion() return require("ai.companion") end

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "AI" }) end
local WARN = vim.log.levels.WARN

-- Methods that put an agent's panel on screen: the ones that show it, and the
-- ones that feed it, which open or start the panel to deliver. Before one
-- runs, the AI slot (lua/ai/slot.lua) hides the other AI windows of this
-- tabpage -- native panels and CodeCompanion chats alike, hidden and never
-- stopped. A feed that stops short -- a prompt editor that never opens --
-- has then hidden them with nothing in their place; hidden only, so they come
-- back the way any hidden chat does. The native-session keys make room their
-- own way (native_key), so a cancelled model question hides nothing.
local REVEALS = {
  toggle = true, focus = true, resume = true, continue = true, edit_prompt = true,
  select_model = true, add_buffer = true, send_selection = true, tree_add = true,
}

---Make room for `provider`'s panel before `method` reveals it. Nothing yields
---while that panel is on screen in any tabpage: the method acts on it where it
---is. Neither moves tabpage nor starts anything from elsewhere -- these callers
---act where they were called from (review delivery has already gone to the
---right tabpage).
local function make_room(method, provider)
  if not REVEALS[method] then return end
  slot().make_room(slot().native_item(provider), { jump = false, editor = false })
end

---Call `method` on one agent's backend, by name: a key that already knows
---which agent it acts on (the one on the right, Claude for its diffs), or
---review feedback for the agent whose round it is.
---@param name string provider
---@param method string
local function call(name, method, ...)
  local fn = backend(name)[method]
  if type(fn) ~= "function" then
    vim.notify(("%s does not support %s"):format(label_of(name), method), WARN)
    return
  end
  return guard(label_of(name), method, function(...)
    make_room(method, name)
    return fn(...)
  end, ...)
end

---Deliver to one agent by name: review feedback goes to the agent whose round
---it is (lua/ai/review). The room made is for that agent's panel, the one
---about to be revealed: every other AI window of this tabpage gives way to
---it, a chat shown here included.
---@param provider string
---@param method string
function M.feed(provider, method, ...)
  if not config.agents[provider] then
    vim.notify(("Unknown AI provider %q"):format(tostring(provider)), WARN)
    return
  end
  return call(provider, method, ...)
end

---Run `fn(item, ...)` for a chat the slot resolved, under the same guard as a
---key: it runs from a picker's callback too, long after the key returned.
local function on_item(what, fn)
  return function(item, ...)
    local label = item.kind == "native" and label_of(item.agent) or "AI chat"
    return guard(label, what, fn, item, ...)
  end
end

-- <leader>ac / <leader>af: the chat on the right (lua/ai/slot.lua), whatever
-- it is. Neither delivers anything, so with nothing on the right they bring
-- the last one back rather than ask.
function M.toggle() return guard("AI chat", "toggle", function() slot().toggle() end) end
function M.focus() return guard("AI chat", "focus", function() slot().focus() end) end

-- The keys only a native agent answers: the one on the right, else the one
-- asked for. A running session is shown and left as it is -- each agent has
-- one session here -- and its backend says so (lua/ai/backend/*); a session
-- one of them starts is announced, as one <leader>an starts is.
---@param why string what a session it starts is for, for that notice
local function native_key(method, why)
  return function()
    return guard("AI", method, function()
      slot().native_target(function(agent)
        guard(label_of(agent), method, function()
          local b, item = backend(agent), slot().native_item(agent)
          local was = b.running()
          -- A cold start that asks something first (claudecode's model
          -- question, backend.asks_first) can still be cancelled: nothing is
          -- hidden for it, and the slot's guard hides the rest once its
          -- terminal does show.
          local asks = not was and (b.asks_first or {})[method]
          if not slot().make_room(item, { hide = not asks }) then return end
          b[method]()
          if not was and b.running() then notify(("Started %s %s"):format(slot().label(item), why)) end
        end)
      end)
    end)
  end
end
M.resume = native_key("resume", "to resume a session")
M.continue = native_key("continue", "to continue its last session")
M.select_model = native_key("select_model", "to pick a model")

---Deliver a captured selection (ai.selection.capture) to `item`: a chat gets
---it fenced in its prompt, Claude a file mention of its lines, Codex the
---draft typed into its input box. Nothing is submitted.
---@param item ai.SlotItem
---@param cap ai.Capture
---@param from integer? the tabpage the key was pressed in
local function deliver_capture(item, cap, from)
  -- A tabpage changed on the way is said once, by went(), not by the jump too.
  if item.kind == "chat" then
    local ok, why = companion().add_capture(item.chat, cap)
    if not ok then return companion().refused(why) end
    companion().show(item.chat, { quiet = true })
  elseif item.agent == "claude" then
    if cap.path == "" then
      return notify("This buffer has no file, and Claude Code takes a selection as a file mention: save it, or <leader>ai",
        vim.log.levels.WARN)
    end
    -- Shown somewhere already (here, a diff tabpage's copy included, or in the
    -- tabpage make_room went to), the mention goes to it as it is: claudecode's
    -- own open would put a second window beside a copy.
    local room = slot().make_room(item, { quiet = true })
    if not room then return end
    if room == "room" then backend("claude").reveal() end
    -- A mention is of the file on disk, so an unsaved edit is not in it. It
    -- still goes -- the lines are the ones selected -- but the user is told,
    -- as Codex's paste-instead notice tells them (<leader>ai sends the text).
    if cap.modified then
      notify("Claude Code reads the saved file; this buffer has unsaved changes, so the mention points at its saved lines"
        .. " (<leader>ai takes the selected text itself)", WARN)
    end
    backend("claude").send_range(cap.path, cap.l1, cap.l2)
  else
    if not cap.draft then return notify(cap.err or "No selection", vim.log.levels.WARN) end
    if cap.notice then notify(cap.notice) end
    if not slot().make_room(item, { quiet = true }) then return end
    backend(item.agent).send_text(cap.draft)
  end
  slot().went(item, from)
end

---The native agent on the right of this tabpage when it takes files from a
---directory listing (ai.config's tree_add capability: Claude Code). Asks
---nothing: a listing's cursor and selection are only read where they are now.
---@return string|nil agent, ai.SlotItem|nil item what is on the right
local function tree_target()
  local item = slot().target_now()
  local agent = item and item.kind == "native" and item.agent
  if agent and config.agents[agent].capabilities.tree_add then return agent, item end
  return nil, item
end

---Why a listing's file or selection went nowhere.
---@param item ai.SlotItem|nil what is on the right
local function tree_refused(item)
  if not item then
    return notify("A directory listing cannot wait for a question: put Claude Code on the right first (<leader>al)",
      WARN)
  end
  notify("Only Claude Code takes files from a directory listing: put it on the right (<leader>al)", WARN)
end

---A directory listing's selection names files, and only a live Visual tells
---which: it goes to Claude Code on the right at once, or nowhere.
local function tree_selection()
  local agent, item = tree_target()
  if agent then return call(agent, "send_selection") end
  vim.cmd("normal! \27")
  tree_refused(item)
end

---<leader>as: the selection, to the chat on the right.
function M.send_selection()
  return guard("AI chat", "send_selection", function()
    if require("ai.selection").is_tree() then return tree_selection() end
    local cap, err = require("ai.selection").capture()
    if not cap then return notify(err, vim.log.levels.WARN) end
    slot().target(on_item("send_selection", function(item, from) deliver_capture(item, cap, from) end),
      { prompt = "Add selection to" })
  end)
end

---<leader>ab: the current buffer, as a file mention, to the native agent on
---the right. A chat takes a selection or its own #{buffer} instead -- so a
---question offers the native agents alone: a chat picked or created there
---would only be refused.
function M.add_buffer()
  return guard("AI chat", "add_buffer", function()
    local buf = vim.api.nvim_get_current_buf()
    local path, modified = vim.api.nvim_buf_get_name(buf), vim.bo[buf].modified
    slot().target(on_item("add_buffer", function(item, from)
      if item.kind == "chat" then
        return notify("A chat takes a selection (<leader>as),\nor #{buffer} / /buffer in its own prompt")
      end
      if path == "" then return notify("Current buffer has no file path", vim.log.levels.WARN) end
      local room = slot().make_room(item, { quiet = true })
      if not room then return end
      if item.agent == "claude" and room == "room" then backend("claude").reveal() end
      -- Both agents read the file from disk, and say so for an unsaved edit.
      backend(item.agent).add_path(path, modified)
      slot().went(item, from)
    end), { prompt = "Add buffer to", native_only = true })
  end)
end

-- Diffs are Claude's alone, whatever is on the right.
function M.accept_diff() return call("claude", "accept_diff") end
function M.deny_diff() return call("claude", "deny_diff") end

---oil's <leader>aS: the file under the cursor, to Claude Code on the right
---(see tree_target); anything else on the right, or nothing, is refused.
function M.tree_add()
  local agent, item = tree_target()
  if agent then return call(agent, "tree_add") end
  tree_refused(item)
end

---Replay the TUI's own image-paste keystroke for each staged file.
---
---Only the CLI can put image bytes into its request, so this is the one channel
---that exists. It runs after the prompt buffer closes because the agent drops
---pty input while it is blocked on the editor.
---@param paths string[]
---@param provider string the agent whose prompt the images belong to
function M.attach_images(paths, provider)
  if not config.agents[provider] then
    -- No agent to guess at: an image sent to the wrong one is worse than none.
    for _, png in ipairs(paths or {}) do vim.fn.delete(png) end
    return notify("The images belong to no known agent's prompt: nothing was attached", WARN)
  end
  return call(provider, "attach_images", paths)
end

local function visual() return vim.fn.mode():sub(1, 1):match("[vVsS\22\19]") ~= nil end

---Open the prompt of the chat on the right.
---
---For a native agent this is the TUI's own ctrl+g, not a buffer of ours:
---`$EDITOR` points at scripts/agent-editor, which brings the prompt back into
---this Nvim. Going through the CLI means the box's existing text arrives
---exactly and the edit is written back by the CLI itself -- see
---lua/ai/editor.lua for why reading the box off the screen instead cannot
---work. A CodeCompanion chat's prompt is its own buffer: the cursor goes there.
---
---From Visual mode the selection goes along: placed in the agent's box first,
---so it shows up in the editor alongside whatever was already typed there, or
---added to the chat's prompt.
function M.compose()
  return guard("AI chat", "compose", function()
    local cap
    if visual() then
      local err
      cap, err = require("ai.selection").capture()
      if not cap then return notify(err, vim.log.levels.WARN) end
    end
    local seed = cap and cap.draft
    local editor = require("ai.editor")
    -- A prompt already open here means that TUI is blocked on it and would
    -- swallow the key; the useful thing is to get back into that buffer --
    -- whoever's it is, one whose path names no agent too.
    if editor.open_here() and editor.focus_open(seed) then return end
    slot().target(on_item("compose", function(item)
      if item.kind == "chat" then
        if cap then
          local ok, why = companion().add_capture(item.chat, cap)
          if not ok then return companion().refused(why) end
        end
        return companion().focus_prompt(item.chat, true)
      end
      if editor.focus_open(seed, item.agent) then return end
      if not slot().make_room(item) then return end
      backend(item.agent).edit_prompt({ seed = seed })
    end), { prompt = "Edit prompt for" })
  end)
end

---After a chat was picked: show it, or give it the selection captured before
---the question.
---@param from integer the tabpage the key was pressed in
local function picked(cap, from)
  return on_item("open", function(item)
    if cap then return deliver_capture(item, cap, from) end
    slot().reveal(item)
  end)
end

local function pick_with(what)
  return function()
    return guard("AI chat", what, function()
      local cap
      if visual() then
        if require("ai.selection").is_tree() then
          vim.cmd("normal! \27")
          return notify("A directory selection cannot wait for a question: use <leader>as with Claude Code on the right",
            vim.log.levels.WARN)
        end
        local err
        cap, err = require("ai.selection").capture()
        if not cap then return notify(err, vim.log.levels.WARN) end
      end
      -- From a CodeDiff view, the chat picked opens in the page it came from;
      -- a cancel goes back to the view.
      local _, from = slot().home()
      if what == "new" then
        slot().pick_new(picked(cap, from), { back = from })
      else
        slot().switch(picked(cap, from), { back = from })
      end
    end)
  end
end

---<leader>an / :AI new: start a chat on any available backend, and show it.
---From Visual mode the selection goes to it.
M.new_chat = pick_with("new")
---<leader>al / :AI: show another open chat. From Visual mode the
---selection goes to it.
M.switch_chat = pick_with("switch")

-- A native agent's own records, read from disk: the agent on the right, else
-- the one asked for (in provider order). Not backend methods, so not `call`;
-- the same guard, so a failing view is a notification like every other
-- <leader>a key.
local function transcript_key(method)
  return function()
    return guard("AI", "transcript", function()
      slot().native_target(function(agent)
        guard(label_of(agent), "transcript", function() require("ai.transcript")[method](agent) end)
      end, { prompt = "Whose transcript?" })
    end)
  end
end
M.transcript = transcript_key("open_current")
M.transcript_pick = transcript_key("pick")

-- The review loop is one for every conversation, so these name no agent. Each
-- loads its module on first use: nothing of it is required at startup.
function M.review()
  return guard("AI review", "open", function() return require("ai.review").open() end)
end
function M.new_round()
  return guard("AI review", "start", function() return require("ai.review.rounds").start() end)
end

---The providers, the key profile and every open chat, for :AI info.
---Never loads claudecode.nvim or CodeCompanion to answer.
function M.info()
  local function set(var) return (vim.env[var] or "") ~= "" end

  local profiles = {}
  for _, name in ipairs(config.key_names()) do
    local p = config.key_profiles[name]
    profiles[name] = { label = p.label, var = p.api_key, set = set(p.api_key) }
  end

  -- Each provider in order, with the parts it offers and whether each can
  -- start here (ai.config.backends: PATH and the environment only).
  local parts = {}
  for _, b in ipairs(config.backends()) do
    parts[b.provider] = parts[b.provider] or {}
    local what = b.kind == "native" and "terminal" or b.kind == "acp" and "ACP" or "API"
    table.insert(parts[b.provider], { what = what, available = b.available })
  end
  local providers = {}
  local cli_keys = {}
  for _, p in ipairs(config.providers) do
    providers[#providers + 1] = { name = p.name, label = p.label, parts = parts[p.name] or {} }
    if p.cli_api_key then cli_keys[p.cli_api_key] = set(p.cli_api_key) end
  end

  -- A summary must not fail on one chat's question.
  local chats = {}
  local ok, items = pcall(slot().list)
  for _, item in ipairs(ok and items or {}) do
    local got, label, where = pcall(function() return slot().label(item), slot().where(item) end)
    if got then chats[#chats + 1] = { id = item.id, label = label, where = where } end
  end

  local chat, http = config.codecompanion.chat_adapter, config.codecompanion.http_adapter
  return {
    providers = providers,
    key = {
      name = config.key.name,
      label = config.key.label,
      auto = config.key.auto,
      var = config.codecompanion.api_key,
      set = config.codecompanion.api_key ~= nil and set(config.codecompanion.api_key),
    },
    profiles = profiles,
    cli_keys = cli_keys,
    codecompanion = {
      chat = chat and (chat .. (chat == config.codecompanion.acp_adapter and " (ACP)" or " (HTTP)"))
        or "CodeCompanion's own default",
      inline = http and (http .. " (HTTP)") or "none (no provider offers api)",
    },
    chats = chats,
  }
end

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end

-- Global keys. Their descriptions are fixed: what a key reaches depends on
-- what each tabpage shows, which a description cannot follow. `<leader>ae` is
-- the one relabelled -- by :AI key, with the profile it bills (apply_keymaps).
--
-- The chat keys (n l c f b s i) act on the chat on the right, whatever it is
-- -- a native agent's terminal or a CodeCompanion chat (lua/ai/slot.lua). The
-- native-session keys (r R m) and the transcript keys (t T) reach the native
-- agent on the right, else the one asked for.
--
-- The CodeCompanion keys (e p o) are owned here rather than by its lazy spec,
-- like the rest; they load the plugin on first use, through `require` or its
-- commands. `<leader>ap` is a leaf -- a `<leader>ap*` mapping would make it
-- wait out 'timeoutlen' again; so are `<leader>an` and `<leader>al`.
local KEYS = {
  -- From Visual mode both take the selection to the chat they open.
  { { "n", "x" }, "n", M.new_chat, "New AI chat…" },
  { { "n", "x" }, "l", M.switch_chat, "Switch AI chat…" },
  { "n", "c", M.toggle, "Toggle AI chat" },
  { "n", "f", M.focus, "Focus AI chat" },
  { "n", "r", M.resume, "Resume native agent…" },
  { "n", "R", M.continue, "Continue native agent…" },
  { "n", "m", M.select_model, "Select native agent model" },
  { "n", "b", M.add_buffer, "Add buffer to AI chat" },
  { "x", "s", M.send_selection, "Add selection to AI chat" },
  -- The agent's own input box loses <C-h/j/k/l> to window navigation, so long
  -- prompts get a real buffer instead -- the agent's own ctrl+g, routed back
  -- here; a chat's prompt is a buffer already. Bound in Visual mode too, where
  -- it seeds from the selection.
  { { "n", "x" }, "i", M.compose, "Edit prompt for AI chat" },
  { "n", "t", M.transcript, "Read native agent transcript" },
  { "n", "T", M.transcript_pick, "Native agent session history" },
  -- Review rounds: a round belongs to a conversation, so neither names an
  -- agent.
  { "n", "v", M.review, "Review changes since round baseline" },
  { "n", "V", M.new_round, "Start a review round" },
  -- The key profile of inline edits and command prompts (API credits).
  { "n", "x", function() require("ai.switch").pick() end, "Switch API key profile" },
  { { "n", "x" }, "p", "<cmd>CodeCompanionActions<cr>", "Companion actions" },
  -- codecompanion-history's browser: every chat it auto-saved, either kind.
  -- A restored chat comes up through upstream's own open; the slot's guard
  -- makes the rest of the tabpage's AI windows give way to it.
  { "n", "o", "<cmd>CodeCompanionHistory<cr>", "Open saved Companion chat" },
}

-- oil is the only directory view in this config (no tree sidebar). Every oil
-- buffer gets the key; whether anything takes the file is decided when it is
-- pressed, by what is on the right (M.tree_add).
---@param buf integer
local function oil_keys(buf)
  vim.keymap.set("n", "<leader>aS", M.tree_add, {
    buffer = buf,
    desc = "Add file under cursor to Claude Code",
    silent = true,
  })
end

---Define, relabel or remove the `<leader>a` keys for the current state.
---Idempotent: called from setup(), after every :AI key, and once
---claudecode.nvim has loaded. which-key rereads the keymaps each time its popup
---opens, so it needs no notice of the change.
function M.apply_keymaps()
  for _, k in ipairs(KEYS) do
    map(k[1], "<leader>a" .. k[2], k[3], k[4])
  end
  -- An expr mapping, so a missing key refuses before the command line opens;
  -- not silent, so the half-typed :CodeCompanion stays visible. From Visual
  -- mode `:` brings the '<,'> range along.
  vim.keymap.set({ "n", "x" }, "<leader>ae", function() return companion().inline_keys() end, {
    expr = true,
    silent = false,
    desc = ("Inline edit · %s (HTTP)"):format(config.key.label),
  })

  -- Claude's diffs arrive through claudecode.nvim, so the keys exist once it
  -- has loaded -- whatever is on the right.
  local diffs = package.loaded["claudecode"] ~= nil
  for lhs, spec in pairs({
    ["<leader>aa"] = { M.accept_diff, "Accept Claude diff" },
    ["<leader>ad"] = { M.deny_diff, "Deny Claude diff" },
  }) do
    if diffs then
      map("n", lhs, spec[1], spec[2])
    else
      pcall(vim.keymap.del, "n", lhs)
    end
  end

  -- Buffer-local keys only: no window is touched.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "oil" then oil_keys(buf) end
  end
end

-- What the review loop needs to hear about from the start: agent terminals and
-- CodeCompanion chats are where rounds come from (lua/ai/review/rounds.lua),
-- and every CodeDiff view gets the review keys (lua/ai/review). Registering
-- these requires none of it; a module is loaded once an event concerns it --
-- a TermOpen only once its terminal turns out to be an agent's. A failure is a
-- warning: it must not break the terminal or the chat that fired it.
local function review_events()
  local group = vim.api.nvim_create_augroup("ai_review_sources", { clear = true })
  local function guarded(what, fn)
    return function(ev)
      local ok, err = xpcall(fn, debug.traceback, ev)
      if not ok then
        vim.notify(("Review %s failed:\n%s"):format(what, err), vim.log.levels.WARN, { title = "AI review" })
      end
    end
  end
  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(ev)
      -- The job's directory when Snacks records none: claudecode leaves `cwd`
      -- unset under claude_cwd = "cwd". Read now, in the terminal's window.
      local cwd = vim.fn.getcwd()
      vim.schedule(guarded("terminal", function()
        if vim.api.nvim_buf_is_valid(ev.buf) and require("util.terminal").agent_of(ev.buf) then
          require("ai.review.rounds").track_terminal(ev.buf, cwd)
        end
      end))
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeCompanionChatCreated",
    callback = guarded("chat", function(ev) require("ai.review.rounds").chat_created(ev.data) end),
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeCompanionChatClosed",
    callback = guarded("chat", function(ev)
      local rounds = package.loaded["ai.review.rounds"]
      if rounds then rounds.chat_closed(ev.data) end
    end),
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffKeys",
    callback = guarded("keys", function(ev)
      local view = require("ai.review")
      if type(view.attach) == "function" then view.attach(ev.data and ev.data.tabpage) end
    end),
  })
end

function M.setup()
  if did_setup then return end
  did_setup = true

  -- Input rules for every agent panel, whichever agent runs in it -- see
  -- lua/ai/terminal.lua.
  require("ai.terminal").setup()

  M.apply_keymaps()

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("ai_tree_keymaps", { clear = true }),
    pattern = { "oil" },
    callback = function(event) oil_keys(event.buf) end,
  })

  review_events()

  -- One AI window per tabpage, whichever path opened it.
  require("ai.slot").setup()

  -- :AI and :AIInfo. Defining them loads no plugin.
  require("ai.switch").setup()
end

return M
