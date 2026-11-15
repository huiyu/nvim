local M = {}

local config

---@param name string an agent (TUI kind, a key of ai.state.agents)
local function backend(name)
  return require("agent_workbench.backend." .. name)
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

local function slot() return require("agent_workbench.slot") end
local function companion() return require("agent_workbench.companion") end

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "AI" }) end
local WARN = vim.log.levels.WARN

-- The methods reached through call() that put an agent's panel on screen:
-- the ones that feed it, which open or start the panel to deliver. Before one
-- runs, the AI slot (local-plugin/agent-workbench.nvim/lua/agent_workbench/slot.lua) hides the other AI windows of this
-- tabpage -- native panels and CodeCompanion chats alike, hidden and never
-- stopped. A feed that stops short -- a prompt editor that never opens --
-- has then hidden them with nothing in their place; hidden only, so they come
-- back the way any hidden chat does. The native-session keys (native_key) and
-- the slot's own keys make room their own way, so a cancelled model question
-- hides nothing.
local REVEALS = { edit_prompt = true, send_selection = true, tree_add = true }

---Make room for `agent`'s panel before `method` reveals it. Nothing yields
---while that panel is on screen in any tabpage: the method acts on it where it
---is. Neither moves tabpage nor starts anything from elsewhere -- these callers
---act where they were called from (review delivery has already gone to the
---right tabpage).
local function make_room(method, agent)
  if not REVEALS[method] then return end
  slot().make_room(slot().native_item(agent), { jump = false, editor = false })
end

---Call `method` on one agent's backend, by name: a key that already knows
---which agent it acts on (the visible native session), or
---review feedback for the agent whose round it is.
---@param name string agent
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
---@param agent string an agent (TUI kind)
---@param method string
function M.feed(agent, method, ...)
  if not config.agents[agent] then
    vim.notify(("Unknown AI agent %q"):format(tostring(agent)), WARN)
    return
  end
  return call(agent, method, ...)
end

---Run `fn(item, ...)` for a chat the slot resolved, under the same guard as a
---key: it runs from a picker's callback too, long after the key returned.
local function on_item(what, fn)
  return function(item, ...)
    local label = item.kind == "native" and label_of(item.agent) or "AI chat"
    return guard(label, what, fn, item, ...)
  end
end

-- <leader>ac / <leader>af: the chat on the right (local-plugin/agent-workbench.nvim/lua/agent_workbench/slot.lua), whatever
-- it is. Neither delivers anything, so with nothing on the right they bring
-- the last one back rather than ask.
function M.toggle() return guard("AI chat", "toggle", function() slot().toggle() end) end
function M.focus(id) if id then return M.show(id) end; return guard("AI chat", "focus", function() slot().focus() end) end

-- The keys only a native agent answers: the one on the right, else the one
-- asked for. A running session is shown and left as it is -- each agent has
-- one session here -- and its backend says so (local-plugin/agent-workbench.nvim/lua/agent_workbench/backend/*); a session
-- one of them starts is announced, as one <leader>an starts is.
---@param why string what a session it starts is for, for that notice
local function native_key(method, why)
  return function()
    return guard("AI", method, function()
      slot().native_target(function(agent)
        guard(label_of(agent), method, function()
          local b, item = backend(agent), slot().native_item(agent)
          local was = b.running()
          -- A cold start that asks something first (backend.asks_first) can still be cancelled: nothing is
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
---it fenced in its prompt; Codex receives the
---draft typed into its input box. Nothing is submitted.
---@param item ai.SlotItem
---@param cap ai.Capture
---@param from integer? the tabpage the key was pressed in
local function deliver_capture(item, cap, from)
  -- A tabpage changed on the way is said once, by went(), not by the jump too.
  if item.kind == "chat" then
    local ok, why = companion().add_capture(item.chat, cap)
    if not ok then return companion().refused(why) end
    slot().show_chat(item.chat, { quiet = true })
  else
    if not cap.draft then return notify(cap.err or "No selection", vim.log.levels.WARN) end
    if cap.notice then notify(cap.notice) end
    if not slot().make_room(item, { quiet = true }) then return end
    backend(item.agent).send_text(cap.draft)
  end
  slot().went(item, from)
end

local function tree_selection()
  vim.cmd("normal! \27")
  notify("Sending a directory listing is unsupported: select a file or code instead", WARN)
end

---<leader>as: the selection, to the chat on the right.
function M.send_selection()
  return guard("AI chat", "send_selection", function()
    if require("agent_workbench.selection").is_tree() then return tree_selection() end
    local cap, err = require("agent_workbench.selection").capture()
    if not cap then return notify(err, vim.log.levels.WARN) end
    slot().target(on_item("send_selection", function(item, from) deliver_capture(item, cap, from) end),
      { prompt = "Add selection to" })
  end)
end

---<leader>ab: the current buffer's file, to the chat on the right. A native
---agent gets a file mention; a CodeCompanion chat gets it as context, as its
---own /buffer adds it (ai.companion.add_buffer).
function M.add_buffer()
  return guard("AI chat", "add_buffer", function()
    local buf = vim.api.nvim_get_current_buf()
    local path, modified = vim.api.nvim_buf_get_name(buf), vim.bo[buf].modified
    local is_file = vim.bo[buf].buftype == ""
    slot().target(on_item("add_buffer", function(item, from)
      if path == "" then return notify("Current buffer has no file path", vim.log.levels.WARN) end
      if item.kind == "chat" then
        -- A terminal, a panel or the chat itself has a name but no file.
        if not is_file then return notify("Current buffer is not a file", WARN) end
        local ok, why = companion().add_buffer(item.chat, buf)
        if not ok then return companion().refused(why) end
        slot().show_chat(item.chat, { quiet = true })
        -- An agent chat is sent the path alone, and its agent reads the file
        -- from disk, as a native agent's mention is.
        if modified and companion().is_acp(item.chat) then
          notify("An agent chat reads the saved file; this buffer has unsaved changes, so it will not see them"
            .. " (<leader>as takes the selected text itself)", WARN)
        end
        return slot().went(item, from)
      end
      local room = slot().make_room(item, { quiet = true })
      if not room then return end
      -- Both agents read the file from disk, and say so for an unsaved edit.
      backend(item.agent).add_path(path, modified)
      slot().went(item, from)
    end), { prompt = "Add file to" })
  end)
end

---Replay the TUI's own image-paste keystroke for each staged file.
---
---Only the CLI can put image bytes into its request, so this is the one channel
---that exists. It runs after the prompt buffer closes because the agent drops
---pty input while it is blocked on the editor.
---@param paths string[]
---@param agent string the agent whose prompt the images belong to
function M.attach_images(paths, agent)
  if not config.agents[agent] then
    -- No agent to guess at: an image sent to the wrong one is worse than none.
    for _, png in ipairs(paths or {}) do vim.fn.delete(png) end
    return notify("The images belong to no known agent's prompt: nothing was attached", WARN)
  end
  return call(agent, "attach_images", paths)
end

local function visual() return vim.fn.mode():sub(1, 1):match("[vVsS\22\19]") ~= nil end

---Open the prompt of the chat on the right.
---
---For a native agent this is the TUI's own ctrl+g, not a buffer of ours:
---`$EDITOR` points at local-plugin/agent-workbench.nvim/scripts/agent-editor, which brings the prompt back into
---this Nvim. Going through the CLI means the box's existing text arrives
---exactly and the edit is written back by the CLI itself -- see
---local-plugin/agent-workbench.nvim/lua/agent_workbench/editor.lua for why reading the box off the screen instead cannot
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
      cap, err = require("agent_workbench.selection").capture()
      if not cap then return notify(err, vim.log.levels.WARN) end
    end
    local seed = cap and cap.draft
    local editor = require("agent_workbench.editor")
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
        return slot().focus_chat_prompt(item.chat, true)
      end
      if editor.focus_open(seed, item.agent) then return end
      if not slot().make_room(item) then return end
      backend(item.agent).edit_prompt({ seed = seed })
    end), { prompt = "Compose prompt for" })
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
        if require("agent_workbench.selection").is_tree() then
          vim.cmd("normal! \27")
          return notify("Sending a directory listing is unsupported: select a file or code instead",
            vim.log.levels.WARN)
        end
        local err
        cap, err = require("agent_workbench.selection").capture()
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
        guard(label_of(agent), "transcript", function() require("agent_workbench.transcript")[method](agent) end)
      end, { prompt = "Whose transcript?" })
    end)
  end
end
M.transcript = transcript_key("open_current")
M.transcript_pick = transcript_key("pick")

-- The review loop is one for every conversation, so these name no agent. Each
-- loads its module on first use: nothing of it is required at startup.
function M.review()
  return guard("AI review", "open", function() return require("agent_workbench.review").open() end)
end
function M.new_round()
  return guard("AI review", "start", function() return require("agent_workbench.review.rounds").start() end)
end

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end

-- Global keys. Their descriptions are fixed: what a key reaches depends on
-- what each tabpage shows, which a description cannot follow. `<leader>ae` is
-- the one relabelled -- by :AI key, with the profile it bills (apply_keymaps).
--
-- The chat keys (n l c f b s i) act on the chat on the right, whatever it is
-- -- a native agent's terminal or a CodeCompanion chat (local-plugin/agent-workbench.nvim/lua/agent_workbench/slot.lua). The
-- native-session keys (r R m) and the transcript keys (t T) reach the native
-- agent on the right, else the one asked for.
--
-- The CodeCompanion keys (e o) are owned here rather than by its lazy spec,
-- like the rest; they load the plugin on first use, through `require` or its
-- commands. `<leader>an` and `<leader>al` are leaves: a longer mapping would
-- make them wait out 'timeoutlen'. The action palette has no key: its chats
-- and prompts are `<leader>an`'s and `<leader>ae`'s, and it stays
-- :CodeCompanionActions.
local KEYS = {
  -- From Visual mode both take the selection to the chat they open.
  { { "n", "x" }, "new_chat", M.new_chat, "New AI chat…" },
  { { "n", "x" }, "switch_chat", M.switch_chat, "Switch AI chat…" },
  { "n", "toggle", M.toggle, "Toggle AI chat" },
  { "n", "focus", M.focus, "Focus AI chat" },
  { "n", "resume", M.resume, "Resume native agent…" },
  { "n", "continue", M.continue, "Continue native agent" },
  { "n", "select_model", M.select_model, "Select native agent model…" },
  { "n", "add_buffer", M.add_buffer, "Add file to AI chat" },
  { "x", "send_selection", M.send_selection, "Add selection to AI chat" },
  -- The agent's own input box loses <C-h/j/k/l> to window navigation, so long
  -- prompts get a real buffer instead -- the agent's own ctrl+g, routed back
  -- here; a chat's prompt is a buffer already. Bound in Visual mode too, where
  -- it seeds from the selection.
  { { "n", "x" }, "compose", M.compose, "Compose prompt for AI chat" },
  { "n", "transcript", M.transcript, "Read native agent transcript" },
  { "n", "transcript_pick", M.transcript_pick, "Browse native agent transcripts" },
  -- Review rounds: a round belongs to a conversation, so neither names an
  -- agent.
  { "n", "review", M.review, "Review changes since round baseline" },
  { "n", "new_round", M.new_round, "Start review round" },
  -- The key profile of inline edits and command prompts (API credits).
  { "n", "key", function() require("agent_workbench.switch").pick() end, "Switch API key profile…" },
  -- codecompanion-history's browser: every chat it auto-saved, either kind.
  -- A restored chat comes up through upstream's own open; the slot's guard
  -- makes the rest of the tabpage's AI windows give way to it.
  { "n", "history", "<cmd>CodeCompanionHistory<cr>", "Browse saved Companion chats" },
}

---Define, relabel or remove the `<leader>a` keys for the current state.
---Idempotent: called at setup and after every :AI key. which-key reads its popup
---opens, so it needs no notice of the change.
function M.apply_keymaps()
  local opts = require("agent_workbench.options").get()
  local keys = opts.keymaps
  if keys == false then return end
  for _, k in ipairs(KEYS) do
    local allowed = (k[2] ~= "review" and k[2] ~= "new_round" or opts.integrations.review)
      and (k[2] ~= "history" and k[2] ~= "key" or opts.integrations.companion)
    if keys[k[2]] and allowed then map(k[1], keys[k[2]], k[3], k[4]) end
  end
  if not opts.integrations.companion or not keys.inline then return end
  -- An expr mapping, so a missing key refuses before the command line opens;
  -- not silent, so the half-typed :CodeCompanion stays visible. From Visual
  -- mode `:` brings the '<,'> range along.
  vim.keymap.set({ "n", "x" }, keys.inline, function() return companion().inline_keys() end, {
    expr = true,
    silent = false,
    desc = ("Inline edit · %s (HTTP)…"):format(config.key.label),
  })


end

-- What the review loop needs to hear about from the start: agent terminals and
-- CodeCompanion chats are where rounds come from (local-plugin/agent-workbench.nvim/lua/agent_workbench/review/rounds.lua),
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
      -- Capture the terminal window's cwd now as a fallback for owner metadata.
      local cwd = vim.fn.getcwd()
      vim.schedule(guarded("terminal", function()
        if vim.api.nvim_buf_is_valid(ev.buf) and require("agent_workbench.terminal").agent_of(ev.buf) then
          require("agent_workbench.review.rounds").track_terminal(ev.buf, cwd)
        end
      end))
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeCompanionChatCreated",
    callback = guarded("chat", function(ev)
      require("agent_workbench.review.rounds").chat_created(ev.data)
      require("agent_workbench.progress").chat_created(ev.data)
    end),
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeCompanionChatClosed",
    callback = guarded("chat", function(ev)
      local rounds = package.loaded["agent_workbench.review.rounds"]
      if rounds then rounds.chat_closed(ev.data) end
    end),
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffKeys",
    callback = guarded("keys", function(ev)
      local view = require("agent_workbench.review")
      if type(view.attach) == "function" then view.attach(ev.data and ev.data.tabpage) end
    end),
  })
end

---Register the public facade; loading the module itself starts nothing.
function M.setup(opts)
  require("agent_workbench.options").setup(opts)
  config = require("agent_workbench.state")
-- Loading the facade installs it, once (require caches the module): init.lua
-- requires it before lazy.nvim, and every later require("agent_workbench") gets the same
-- table. Nothing below may require("agent_workbench") synchronously -- the module is still
-- loading, so that require fails with "loop or previous error" -- use M.

-- Input rules for every agent panel, whichever agent runs in it -- see
-- local-plugin/agent-workbench.nvim/lua/agent_workbench/terminal.lua.
require("agent_workbench.terminal").setup()

M.apply_keymaps()


if require("agent_workbench.options").get().integrations.review then review_events() end

-- One AI window per tabpage, whichever path opened it.
require("agent_workbench.slot").setup()

-- A key switch (:AI key, <leader>ax) relabels <leader>ae: ai.switch announces
-- it, and the keys are this module's.
vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("ai_keymaps", { clear = true }),
  pattern = "AIStateChanged",
  callback = function() M.apply_keymaps() end,
})

-- :AI and :AIInfo, the typed twins of <leader>al / an / ax. Defining them
-- loads no plugin; the key profile's subcommands are ai.switch's.
vim.api.nvim_create_user_command("AI", function(o)
  local sub, arg = o.fargs[1], o.fargs[2]
  -- The chat pickers of <leader>al / <leader>an (local-plugin/agent-workbench.nvim/lua/agent_workbench/slot.lua).
  if not sub then return M.switch_chat() end
  if sub == "provider" then
    return notify(":AI provider is gone: :AI new (<leader>an) picks each chat's backend;"
      .. "\nthe picker lists the providers in the order of lua/config/ai.lua", vim.log.levels.ERROR)
  end
  if #o.fargs <= 2 then
    if sub == "key" then return require("agent_workbench.switch").key(arg) end
    if sub == "info" and not arg then return require("agent_workbench.switch").info() end
    if sub == "new" and not arg then return M.new_chat() end
  end
  notify("Usage: :AI [new | key [name] | info]", vim.log.levels.ERROR)
end, {
  nargs = "*",
  complete = function(...) return require("agent_workbench.switch").complete(...) end,
  desc = "Switch AI chat, start one, or set API key profile",
})
vim.api.nvim_create_user_command("AIInfo", function() require("agent_workbench.switch").info() end,
  { desc = "Show AI providers, key profile and open chats" })

end

---Copied public session identity, independent of the chosen terminal provider.
function M.session_of_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then return nil end
  local info = vim.b[buf].agent_workbench
  local agent = type(info) == "table" and config and config.agents[info.kind]
  if not agent then return nil end
  return { id = info.id, kind = info.kind, label = agent.label, root = info.cwd, buf = buf, generation = info.generation }
end
function M.sessions()
  local registry = package.loaded["agent_workbench.terminal_provider"]
  return registry and registry.sessions() or {}
end
function M.session(id)
  local kind = id:gsub("^native:", "")
  local registry = package.loaded["agent_workbench.terminal_provider"]
  return registry and registry.session(kind) or nil
end
function M.backends() return vim.deepcopy(config.backends()) end
function M.options() return require("agent_workbench.options").get() end
function M.open(id, opts)
  opts = opts or {}
  local kind = id:gsub("^native:", "")
  if not config.agents[kind] then return nil, { code = "unavailable", message = "Native backend is not enabled: " .. kind } end
  local item = slot().native_item(kind)
  if not slot().make_room(item) then return nil, { code = "cancelled", message = "No room for the native session" } end
  local method = ({ new = "reveal", resume = "resume", continue = "continue", model = "select_model" })[opts.mode or "new"]
  assert(method, "Unknown native open mode")
  local ok, err = pcall(backend(kind)[method])
  if not ok then return nil, { code = "unavailable", message = tostring(err) } end
  return M.session(kind)
end
function M.show(id) return M.open(id) end
function M.hide(id)
  local kind = id:gsub("^native:", "")
  if not config.agents[kind] then return false, { code = "unavailable", message = "Unknown native backend" } end
  return backend(kind).hide()
end
function M.stop(id)
  local kind = id:gsub("^native:", "")
  if not config.agents[kind] then return false, { code = "unavailable", message = "Unknown native backend" } end
  return backend(kind).stop()
end
---Deliver captured context without submitting the CLI's input box.
---@param id string native backend id
---@param capture {text?: string, path?: string, modified?: boolean}
function M.send_context(id, capture)
  local kind = id:gsub("^native:", "")
  if not config.agents[kind] then return false, { code = "unavailable", message = "Unknown native backend" } end
  if type(capture) ~= "table" or type(capture.text) ~= "string" and type(capture.path) ~= "string" then
    return false, { code = "unsupported", message = "Context needs text or an absolute file path" }
  end
  local shown, err = M.open(kind)
  if not shown then return false, err end
  if capture.text ~= nil then backend(kind).send_text(capture.text)
  else backend(kind).add_path(capture.path, capture.modified) end
  return true
end
M.key = {
  use = function(name) return require("agent_workbench.switch").key(name) end,
  info = function() return { selected = config.key_setting(), profile = vim.deepcopy(config.key) } end,
}

return M
