local M = {}

local config = require("ai.config")
local did_setup = false

local function backend()
  return require("ai.backend." .. config.provider)
end

--- Run `fn` for `method` and turn a failure into a notification: the facade
--- is reached from mappings, where an escaped error is a traceback.
local function guard(method, fn, ...)
  local args = { ... }
  local ok, result = xpcall(function() return fn(unpack(args)) end, debug.traceback)
  if not ok then
    vim.notify(("%s %s failed:\n%s"):format(config.label, method, result), vim.log.levels.ERROR)
    return
  end
  return result
end

local function invoke(method, ...)
  local fn = backend()[method]
  if type(fn) ~= "function" then
    vim.notify(("%s does not support %s"):format(config.label, method), vim.log.levels.WARN)
    return
  end
  return guard(method, fn, ...)
end

function M.toggle() return invoke("toggle") end
function M.focus() return invoke("focus") end
function M.resume() return invoke("resume") end
function M.continue() return invoke("continue") end
function M.select_model() return invoke("select_model") end
function M.add_buffer() return invoke("add_buffer") end
function M.send_selection() return invoke("send_selection") end
function M.accept_diff() return invoke("accept_diff") end
function M.deny_diff() return invoke("deny_diff") end
function M.tree_add() return invoke("tree_add") end

---Replay the TUI's own image-paste keystroke for each staged file.
---
---Only the CLI can put image bytes into its request, so this is the one channel
---that exists. It runs after the prompt buffer closes because the agent drops
---pty input while it is blocked on the editor.
---@param paths string[]
function M.attach_images(paths) return invoke("attach_images", paths) end

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
  return guard("transcript", function() return require("ai.transcript").open_current() end)
end
function M.transcript_pick()
  return guard("transcript_pick", function() return require("ai.transcript").pick() end)
end

function M.info()
  return {
    provider = config.provider,
    label = config.label,
    native = config.native.command,
    codecompanion = {
      chat = config.codecompanion.acp_adapter .. " (ACP)",
      inline = config.codecompanion.http_adapter .. " (HTTP)",
    },
  }
end

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end

function M.setup()
  if did_setup then return end
  did_setup = true

  -- Input rules for the agent panel itself, independent of which provider owns
  -- it -- see lua/ai/terminal.lua.
  require("ai.terminal").setup()

  map("n", "<leader>ac", M.toggle, "Toggle " .. config.label)
  map("n", "<leader>af", M.focus, "Focus " .. config.label)
  map("n", "<leader>ar", M.resume, "Resume " .. config.label)
  map("n", "<leader>aR", M.continue, "Continue " .. config.label)
  map("n", "<leader>am", M.select_model, "Select AI model")
  map("n", "<leader>ab", M.add_buffer, "Add buffer to " .. config.label)
  map("x", "<leader>as", M.send_selection, "Attach selection to " .. config.label)

  -- The agent's own input box loses <C-h/j/k/l> to window navigation, so long
  -- prompts get a real buffer instead -- the agent's own ctrl+g, routed back
  -- here. Bound in Visual mode too, where it seeds from the selection.
  map({ "n", "x" }, "<leader>ai", M.compose, "Edit " .. config.label .. " prompt")
  map("n", "<leader>at", M.transcript, "Read " .. config.label .. " transcript")
  map("n", "<leader>aT", M.transcript_pick, config.label .. " session history")

  if config.native.capabilities.diff then
    map("n", "<leader>aa", M.accept_diff, "Accept AI diff")
    map("n", "<leader>ad", M.deny_diff, "Deny AI diff")
  end

  if config.native.capabilities.tree_add then
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("ai_tree_keymaps", { clear = true }),
      pattern = { "NvimTree", "neo-tree", "oil", "minifiles", "snacks_picker_list" },
      callback = function(event)
        vim.keymap.set("n", "<leader>aS", M.tree_add, {
          buffer = event.buf,
          desc = "Add file from tree to " .. config.label,
          silent = true,
        })
      end,
    })
  end

  vim.api.nvim_create_user_command("AIInfo", function()
    local info = M.info()
    vim.notify(vim.inspect(info), vim.log.levels.INFO, { title = "AI provider" })
  end, { desc = "Show the active AI provider and adapters" })
end

return M
