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

-- Methods that put the active provider's panel on screen.
local REVEALS = { toggle = true, focus = true, resume = true, continue = true, edit_prompt = true }

-- One agent panel per tabpage: before the active provider's panel opens here,
-- the other provider's panel in this tabpage is hidden -- hidden, never
-- stopped, so its job and tmux client keep running. Nothing happens while the
-- active panel is already on screen in any tabpage: then the method shows or
-- hides that window where it is, and opens nothing here, so two panels placed
-- side by side by hand do not hide each other either.
local function make_room(method)
  if not REVEALS[method] then return end
  local active = backend()
  if active.window and active.window() then return end
  for _, name in ipairs(config.names()) do
    if name ~= config.provider then
      local other = backend(name)
      if other.visible and other.visible() then pcall(other.hide) end
    end
  end
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
    if name == config.provider then make_room(method) end
    return fn(...)
  end, ...)
end

local function invoke(method, ...)
  return invoke_on(config.provider, method, ...)
end

function M.toggle() return invoke("toggle") end
function M.focus() return invoke("focus") end
function M.resume() return invoke("resume") end
function M.continue() return invoke("continue") end
function M.select_model() return invoke("select_model") end
function M.add_buffer() return invoke("add_buffer") end
function M.send_selection() return invoke("send_selection") end
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
---@param provider string? the agent whose prompt the images belong to; the
---active provider when nil
function M.attach_images(paths, provider)
  return invoke_on(provider or config.provider, "attach_images", paths)
end

---Open the agent's prompt editor.
---
---This is the TUI's own ctrl+g, not a buffer of ours: `$EDITOR` points at
---scripts/agent-editor, which brings the prompt back into this Nvim. Going
---through the CLI means the box's existing text arrives exactly and the edit is
---written back by the CLI itself -- see lua/ai/editor.lua for why reading the
---box off the screen instead cannot work.
---
---From Visual mode the selection is placed in the box first, so it shows up in
---the editor alongside whatever was already typed there.
function M.compose()
  local seed
  if vim.fn.mode():sub(1, 1):match("[vVsS\22\19]") then
    seed = require("ai.selection").draft()
    -- Leave Visual explicitly. The composer this replaced dropped out of it by
    -- opening a buffer; sending bytes to a terminal does not, and the selection
    -- has already been read by this point.
    vim.cmd("normal! \27")
  end
  -- A prompt already open means the TUI is blocked on it and would swallow the
  -- key; the useful thing is to get back into that buffer.
  if require("ai.editor").focus_open(seed) then return end
  return invoke("edit_prompt", { seed = seed })
end

-- Not backend methods, so not `invoke`; the same guard, so a failing view is
-- a notification like every other <leader>a key.
function M.transcript()
  return guard(config.label, "transcript", function() return require("ai.transcript").open_current() end)
end
function M.transcript_pick()
  return guard(config.label, "transcript_pick", function() return require("ai.transcript").pick() end)
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

-- Global native keys. `%{agent}` is the active provider's label, substituted
-- whenever the keys are (re)applied, so which-key names the agent a key will
-- actually reach after a switch.
local KEYS = {
  { "n", "c", M.toggle, "Toggle %{agent}" },
  { "n", "f", M.focus, "Focus %{agent}" },
  { "n", "r", M.resume, "Resume %{agent}" },
  { "n", "R", M.continue, "Continue %{agent}" },
  { "n", "m", M.select_model, "Select AI model" },
  { "n", "b", M.add_buffer, "Add buffer to %{agent}" },
  { "x", "s", M.send_selection, "Attach selection to %{agent}" },
  -- The agent's own input box loses <C-h/j/k/l> to window navigation, so long
  -- prompts get a real buffer instead -- the agent's own ctrl+g, routed back
  -- here. Bound in Visual mode too, where it seeds from the selection.
  { { "n", "x" }, "i", M.compose, "Edit %{agent} prompt" },
  { "n", "t", M.transcript, "Read %{agent} transcript" },
  { "n", "T", M.transcript_pick, "%{agent} session history" },
  { "n", "x", function() require("ai.switch").pick() end, "Switch AI provider / API key" },
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
  local subst = { agent = config.label }
  for _, k in ipairs(KEYS) do
    map(k[1], "<leader>a" .. k[2], k[3], (k[4]:gsub("%%{(%w+)}", subst)))
  end

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

  -- :AI and :AIInfo. Defining them loads no plugin.
  require("ai.switch").setup()
end

return M
