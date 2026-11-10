local M = {}

local config = require("ai.config")
local did_setup = false

---@param name string? a provider; nil means the active one
local function backend(name)
  return require("ai.backend." .. (name or config.provider))
end

local function label_of(name)
  return config.providers[name].label
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

-- Methods that put an agent's panel on screen: the ones that show it, and the
-- ones that feed it, which open or start the panel to deliver. Before one
-- runs, the AI slot (lua/ai/slot.lua) hides the other AI windows of this
-- tabpage -- native panels and CodeCompanion chats alike, hidden and never
-- stopped. A feed that stops short -- a buffer with no file name, a cancelled
-- model picker -- has then hidden them with nothing in their place; hidden
-- only, so they come back the way any hidden chat does.
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

---Call `method` on one provider's backend, whichever is active.
---@param name string provider
---@param method string
local function invoke_on(name, method, ...)
  local fn = backend(name)[method]
  if type(fn) ~= "function" then
    vim.notify(("%s does not support %s"):format(label_of(name), method), vim.log.levels.WARN)
    return
  end
  return guard(label_of(name), method, function(...)
    if name == config.provider then make_room(method, name) end
    return fn(...)
  end, ...)
end

local function invoke(method, ...)
  return invoke_on(config.provider, method, ...)
end

---Deliver to one agent by name, whichever provider is active: review feedback
---goes to the agent whose round it is (lua/ai/review). The room made is for
---that agent's panel, the one about to be revealed: every other AI window of
---this tabpage gives way to it, a chat shown here included.
---@param provider string
---@param method string
function M.feed(provider, method, ...)
  if not config.providers[provider] then
    vim.notify(("Unknown AI provider %q"):format(tostring(provider)), vim.log.levels.WARN)
    return
  end
  local fn = backend(provider)[method]
  if type(fn) ~= "function" then
    vim.notify(("%s does not support %s"):format(label_of(provider), method), vim.log.levels.WARN)
    return
  end
  return guard(label_of(provider), method, function(...)
    make_room(method, provider)
    return fn(...)
  end, ...)
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
-- one session here -- and its backend says so (lua/ai/backend/*).
local function native_key(method)
  return function()
    return guard("AI", method, function()
      slot().native_target(function(agent)
        guard(label_of(agent), method, function()
          if slot().make_room(slot().native_item(agent)) then backend(agent)[method]() end
        end)
      end)
    end)
  end
end
M.resume = native_key("resume")
M.continue = native_key("continue")
M.select_model = native_key("select_model")

---Deliver a captured selection (ai.selection.capture) to `item`: a chat gets
---it fenced in its prompt, Claude a file mention of its lines, Codex the
---draft typed into its input box. Nothing is submitted.
---@param item ai.SlotItem
---@param cap ai.Capture
---@param from integer? the tabpage the key was pressed in
local function deliver_capture(item, cap, from)
  if item.kind == "chat" then
    local ok, why = companion().add_capture(item.chat, cap)
    if not ok then return companion().refused(why) end
    companion().show(item.chat)
  elseif item.agent == "claude" then
    if cap.path == "" then
      return notify("This buffer has no file, and Claude Code takes a selection as a file mention: save it, or <leader>ai",
        vim.log.levels.WARN)
    end
    -- Shown somewhere already (here, a diff tabpage's copy included, or in the
    -- tabpage make_room went to), the mention goes to it as it is: claudecode's
    -- own open would put a second window beside a copy.
    local room = slot().make_room(item)
    if not room then return end
    if room == "room" then backend("claude").reveal() end
    backend("claude").send_range(cap.path, cap.l1, cap.l2)
  else
    if not cap.draft then return notify(cap.err or "No selection", vim.log.levels.WARN) end
    if cap.notice then notify(cap.notice) end
    if not slot().make_room(item) then return end
    backend(item.agent).send_text(cap.draft)
  end
  slot().went(item, from)
end

---A directory listing's selection names files, and only a live Visual tells
---which: it goes to Claude Code on the right at once, or nowhere.
local function tree_selection()
  local item = slot().target_now()
  if item and item.kind == "native" and item.agent == "claude" then
    return invoke_on("claude", "send_selection")
  end
  vim.cmd("normal! \27")
  if not item then
    return notify("A directory selection cannot wait for a question: put Claude Code on the right first (<leader>al)",
      vim.log.levels.WARN)
  end
  notify("Only Claude Code takes files from a directory listing", vim.log.levels.WARN)
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
        return notify("A chat takes a selection (<leader>as), or #{buffer} or /buffer in its own prompt")
      end
      if path == "" then return notify("Current buffer has no file path", vim.log.levels.WARN) end
      local room = slot().make_room(item)
      if not room then return end
      if item.agent == "claude" then
        if room == "room" then backend("claude").reveal() end
        backend("claude").add_path(path)
      else
        backend(item.agent).add_path(path, modified)
      end
      slot().went(item, from)
    end), { prompt = "Add buffer to", native_only = true })
  end)
end

-- Diffs are Claude's alone, and one opened before a switch away still needs
-- an answer, so these never follow the active provider.
function M.accept_diff() return invoke_on("claude", "accept_diff") end
function M.deny_diff() return invoke_on("claude", "deny_diff") end
function M.tree_add() return invoke("tree_add") end

---Replay the TUI's own image-paste keystroke for each staged file.
---
---Only the CLI can put image bytes into its request, so this is the one channel
---that exists. It runs after the prompt buffer closes because the agent drops
---pty input while it is blocked on the editor.
---@param paths string[]
---@param provider string the agent whose prompt the images belong to
function M.attach_images(paths, provider)
  if not config.providers[provider] then
    -- No agent to guess at: an image sent to the wrong one is worse than none.
    for _, png in ipairs(paths or {}) do vim.fn.delete(png) end
    return notify("The images belong to no known agent's prompt: nothing was attached", vim.log.levels.WARN)
  end
  return invoke_on(provider, "attach_images", paths)
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
---<leader>al / :AI chats: show another open chat. From Visual mode the
---selection goes to it.
M.switch_chat = pick_with("switch")

-- Not backend methods, so not `invoke`; the same guard, so a failing view is
-- a notification like every other <leader>a key.
function M.transcript()
  return guard(config.label, "transcript", function() return require("ai.transcript").open_current() end)
end
function M.transcript_pick()
  return guard(config.label, "transcript_pick", function() return require("ai.transcript").pick() end)
end

-- The review loop is one for every conversation, so these name no agent. Each
-- loads its module on first use: nothing of it is required at startup.
function M.review()
  return guard("AI review", "open", function() return require("ai.review").open() end)
end
function M.new_round()
  return guard("AI review", "start", function() return require("ai.review.rounds").start() end)
end

---State of both axes and of both native agents. Never loads claudecode.nvim
---or CodeCompanion to answer.
function M.info()
  local function set(var) return (vim.env[var] or "") ~= "" end

  local profiles = {}
  for _, name in ipairs(config.key_names()) do
    local p = config.key_profiles[name]
    profiles[name] = { label = p.label, var = p.api_key, set = set(p.api_key) }
  end

  -- A summary must not fail on one backend's question.
  local function ask(fn)
    if not fn then return false end
    local ok, value = pcall(fn)
    return ok and value == true
  end

  local sessions, cli_keys = {}, {}
  for _, name in ipairs(config.names()) do
    local b = backend(name)
    sessions[name] = { label = label_of(name), running = ask(b.running), visible = ask(b.visible) }
    local var = config.providers[name].cli_api_key
    cli_keys[var] = set(var)
  end

  local chats
  local plugin = require("lazy.core.config").plugins["codecompanion.nvim"]
  if plugin and plugin._.loaded then
    chats = {}
    local ok, list = pcall(function() return require("codecompanion").buf_get_chat() end)
    for _, entry in ipairs(ok and list or {}) do
      local adapter = entry.chat and entry.chat.adapter
      local name = adapter and adapter.name or "?"
      chats[name] = (chats[name] or 0) + 1
    end
  end

  return {
    provider = config.provider,
    label = config.label,
    native = config.native.command,
    startup = vim.deepcopy(config.startup),
    key = {
      name = config.key.name,
      label = config.key.label,
      auto = config.key.auto,
      var = config.codecompanion.api_key,
      set = set(config.codecompanion.api_key),
    },
    profiles = profiles,
    cli_keys = cli_keys,
    sessions = sessions,
    codecompanion = {
      chat = config.codecompanion.acp_adapter .. " (ACP)",
      inline = config.codecompanion.http_adapter .. " (HTTP)",
    },
    chats = chats,
  }
end

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end

---A CodeCompanion key. lua/ai/companion.lua reaches into CodeCompanion's chat
---internals, so an upgrade that breaks them falls back to the nearest
---upstream command with a WARN -- or, without one, reports the error -- rather
---than ending in a traceback.
---@param what string
---@param fn fun()
---@param fallback string? an Ex command
local function companion_key(what, fn, fallback)
  return function()
    local ok, err = xpcall(fn, debug.traceback)
    if ok then return end
    if not fallback then
      vim.notify(("Companion %s failed:\n%s"):format(what, err), vim.log.levels.ERROR)
      return
    end
    vim.notify(("Companion %s fell back to :%s\n%s"):format(what, fallback, err), vim.log.levels.WARN)
    -- A range fallback reads '< and '>, which only mark this selection once
    -- Visual has been left.
    if vim.fn.mode():match("^[vV\22]") then vim.cmd("normal! \27") end
    vim.cmd(fallback)
  end
end

-- Global keys. `%{agent}` is the active provider's label and `%{key}` the
-- active key profile's, substituted whenever the keys are (re)applied, so
-- which-key names what a key will actually reach after a switch.
--
-- The chat keys (n l c f b s i) act on the chat on the right, whatever it is
-- -- a native agent's terminal or a CodeCompanion chat (lua/ai/slot.lua) --
-- so their descriptions name no agent. The native-session keys (r R m) reach
-- the native agent on the right, else the one asked for.
--
-- The CodeCompanion keys (g G h H e p o) are owned here rather than by its lazy
-- spec so a switch can relabel them; they load the plugin on first use, through
-- `require`. Normal mode goes to a chat, Visual mode takes the selection
-- along. `<leader>ap` is a leaf -- a `<leader>ap*` mapping would make it wait
-- out 'timeoutlen' again; so are `<leader>an` and `<leader>al`.
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
  { "n", "t", M.transcript, "Read %{agent} transcript" },
  { "n", "T", M.transcript_pick, "%{agent} session history" },
  -- Review rounds: a round belongs to a conversation, not to the active
  -- provider, so neither description changes on a switch.
  { "n", "v", M.review, "Review changes since round baseline" },
  { "n", "V", M.new_round, "Start a review round" },
  { "n", "x", function() require("ai.switch").pick() end, "Switch AI provider / API key" },
  -- Agent chat: the active provider over ACP, on the subscription.
  { "n", "g", companion_key("toggle", function() companion().toggle("acp") end, "CodeCompanionChat Toggle"),
    "Agent chat · %{agent} (ACP)" },
  { "x", "g", companion_key("add", function() companion().add_selection("acp") end, "'<,'>CodeCompanionChat Add"),
    "Add selection to agent chat · %{agent}" },
  -- "New" is CodeCompanion's public chat() already, so it has no fallback.
  { "n", "G", companion_key("new chat", function() companion().new("acp") end), "New agent chat · %{agent} (ACP)" },
  -- API chat: the active key profile over HTTP, on API credits.
  { "n", "h", companion_key("toggle", function() companion().toggle("http") end, "CodeCompanionChat Toggle"),
    "API chat · %{key} (HTTP)" },
  { "x", "h", companion_key("add", function() companion().add_selection("http") end, "'<,'>CodeCompanionChat Add"),
    "Add selection to API chat · %{key}" },
  { "n", "H", companion_key("new chat", function() companion().new("http") end), "New API chat · %{key} (HTTP)" },
  { { "n", "x" }, "p", "<cmd>CodeCompanionActions<cr>", "Companion actions" },
  -- codecompanion-history's browser: every chat it auto-saved, either kind.
  -- A restored chat comes up through upstream's own open; the slot's guard
  -- makes the rest of the tabpage's AI windows give way to it.
  { "n", "o", "<cmd>CodeCompanionHistory<cr>", "Open saved Companion chat" },
}

-- oil is the only directory view in this config (no tree sidebar), so the
-- backend's tree-add command is offered there alone, and only while the active
-- provider has one.
---@param buf integer
local function oil_keys(buf)
  if config.native.capabilities.tree_add then
    vim.keymap.set("n", "<leader>aS", M.tree_add, {
      buffer = buf,
      desc = "Add file under cursor to " .. config.label,
      silent = true,
    })
  else
    pcall(vim.keymap.del, "n", "<leader>aS", { buffer = buf })
  end
end

---Define, relabel or remove the `<leader>a` keys for the current state.
---Idempotent: called from setup(), after every :AI switch, and once
---claudecode.nvim has loaded. which-key rereads the keymaps each time its popup
---opens, so it needs no notice of the change.
function M.apply_keymaps()
  local subst = { agent = config.label, key = config.key.label }
  for _, k in ipairs(KEYS) do
    map(k[1], "<leader>a" .. k[2], k[3], (k[4]:gsub("%%{(%w+)}", subst)))
  end
  -- An expr mapping, so a missing key refuses before the command line opens;
  -- not silent, so the half-typed :CodeCompanion stays visible. From Visual
  -- mode `:` brings the '<,'> range along.
  vim.keymap.set({ "n", "x" }, "<leader>ae", function() return companion().inline_keys() end, {
    expr = true,
    silent = false,
    desc = ("Inline edit · %s (HTTP)"):format(config.key.label),
  })

  -- Claude's diffs can arrive while Claude is active or, after a switch away,
  -- from a session claudecode.nvim is still connected to.
  local diffs = config.is("claude") or package.loaded["claudecode"] ~= nil
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

  -- Input rules for every agent panel, whichever provider owns it -- see
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
