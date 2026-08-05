local M = {}

local config = require("ai.config")
local did_setup = false

local function backend()
  return require("ai.backend." .. config.provider)
end

local function invoke(method, ...)
  local fn = backend()[method]
  if type(fn) ~= "function" then
    vim.notify(("%s does not support %s"):format(config.label, method), vim.log.levels.WARN)
    return
  end

  local args = { ... }
  local ok, result = xpcall(function() return fn(unpack(args)) end, debug.traceback)
  if not ok then
    vim.notify(("%s %s failed:\n%s"):format(config.label, method, result), vim.log.levels.ERROR)
    return
  end
  return result
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

  map("n", "<leader>ac", M.toggle, "Toggle " .. config.label)
  map("n", "<leader>af", M.focus, "Focus " .. config.label)
  map("n", "<leader>ar", M.resume, "Resume " .. config.label)
  map("n", "<leader>aR", M.continue, "Continue " .. config.label)
  map("n", "<leader>am", M.select_model, "Select AI model")
  map("n", "<leader>ab", M.add_buffer, "Add buffer to " .. config.label)
  map("x", "<leader>as", M.send_selection, "Attach selection to " .. config.label)

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
