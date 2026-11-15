-- Supported consumer options. Requiring this module registers nothing.
local M = {}
local defaults = {
  providers = { { name = "codex", label = "Codex", cli_api_key = "OPENAI_API_KEY", tui = { kind = "codex" } } },
  key_profile = "auto",
  panel = { width = 90 },
  terminal = { provider = "native" },
  native = { codex = { command = "codex", args = { "--no-alt-screen", "--yolo" }, wrap_tmux = true } },
  integrations = { companion = false, review = false },
  plugin_dirs = {},
  keymaps = false,
  callbacks = {},
}
local effective

---@class AgentWorkbenchOptions
---@field providers? table[] Ordered list; replaces defaults, never index-merges.
---@field key_profile? string HTTP profile for inline/cmd only.
---@field panel? {width?: integer}
---@field terminal? {provider?: "native"|"snacks"|table}
---@field native? table Native launch preferences.
---@field integrations? {companion?: boolean, review?: boolean}
---@field review? table Review policy, overridden live by vim.g.ai_review.
---@field keymaps? false|table Host key choices; false installs no mappings.
---@field callbacks? table Optional host editor/root/error callbacks.

---@param opts? AgentWorkbenchOptions
function M.setup(opts)
  assert(effective == nil, "agent_workbench.setup() can only run once")
  opts = vim.deepcopy(opts or {})
  for key in pairs(opts) do assert(defaults[key] ~= nil or key == "review", "Unknown agent_workbench option: " .. key) end
  local value = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  if opts.providers then value.providers = vim.deepcopy(opts.providers) end
  if opts.plugin_dirs then value.plugin_dirs = vim.deepcopy(opts.plugin_dirs) end
  if opts.native and opts.native.codex and opts.native.codex.args ~= nil then
    value.native.codex.args = vim.deepcopy(opts.native.codex.args)
  end
  local function fields(table_value, allowed, path)
    assert(type(table_value) == "table", path .. " must be a table")
    for key in pairs(table_value) do assert(allowed[key], path .. "." .. tostring(key) .. " is not a supported setting") end
  end
  fields(value.panel, { width = true }, "agent_workbench.panel")
  fields(value.terminal, { provider = true }, "agent_workbench.terminal")
  fields(value.integrations, { companion = true, review = true }, "agent_workbench.integrations")
  fields(value.native, { codex = true }, "agent_workbench.native")
  fields(value.native.codex, { command = true, args = true, wrap_tmux = true }, "agent_workbench.native.codex")
  for key, enabled in pairs(value.integrations) do
    assert(type(enabled) == "boolean", "agent_workbench.integrations." .. key .. " must be boolean")
  end
  assert(value.keymaps == false or type(value.keymaps) == "table", "agent_workbench.keymaps must be false or a table")
  assert(type(value.key_profile) == "string" and value.key_profile ~= "", "agent_workbench.key_profile must be a profile name")
  assert(type(value.native.codex.command) == "string" and value.native.codex.command ~= "", "agent_workbench.native.codex.command must name an executable")
  assert(vim.islist(value.native.codex.args), "agent_workbench.native.codex.args must be an argv list")
  for i, arg in ipairs(value.native.codex.args) do assert(type(arg) == "string", "agent_workbench.native.codex.args[" .. i .. "] must be a string") end
  assert(type(value.native.codex.wrap_tmux) == "boolean", "agent_workbench.native.codex.wrap_tmux must be boolean")
  assert(vim.islist(value.plugin_dirs), "agent_workbench.plugin_dirs must be an ordered list")
  for i, dir in ipairs(value.plugin_dirs) do assert(type(dir) == "string" and dir ~= "", "agent_workbench.plugin_dirs[" .. i .. "] must be a directory path") end
  assert(type(value.panel.width) == "number" and value.panel.width >= 1 and value.panel.width % 1 == 0,
  "agent_workbench.panel.width must be a positive integer")
  assert(type(value.terminal.provider) == "table" or value.terminal.provider == "native" or value.terminal.provider == "snacks",
  "agent_workbench.terminal.provider must be native, snacks or a provider table")
  if type(value.terminal.provider) == "table" then
    assert(value.terminal.provider.embedded ~= false, "External terminal providers are not supported in this release")
    for _, method in ipairs({ "open", "show", "hide", "send", "alive", "stop" }) do
      assert(type(value.terminal.provider[method]) == "function", "agent_workbench.terminal.provider missing " .. method)
    end
  end
  fields(value.callbacks, { project_root = true, editor_win = true, origin_tab = true, notify_error = true }, "agent_workbench.callbacks")
  for key, fn in pairs(value.callbacks) do assert(type(fn) == "function", "agent_workbench.callbacks." .. key .. " must be a function") end
  if value.keymaps then
    for key, lhs in pairs(value.keymaps) do
      assert(lhs == false or type(lhs) == "string" and lhs ~= "", "agent_workbench.keymaps." .. key .. " must be a key or false")
    end
  end
  value.review = vim.tbl_deep_extend("force", vim.deepcopy(require("agent_workbench.review.defaults")), value.review or {})
  require("agent_workbench.review.settings").validate(value.review)
  effective = value
end

function M.get() return vim.deepcopy(effective or defaults) end
function M.callback(name) return (effective or defaults).callbacks[name] end

return M
