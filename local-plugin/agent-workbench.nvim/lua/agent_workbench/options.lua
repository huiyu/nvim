-- Supported consumer options. Requiring this module registers nothing.
local M = {}
local defaults = {
  providers = { { name = "codex", label = "Codex", cli_api_key = "OPENAI_API_KEY", tui = { kind = "codex" } } },
  key_profile = "auto",
  panel = { width = 90 },
  terminal = { provider = "native" },
  native = { codex = { command = "codex", args = { "--no-alt-screen", "--yolo" }, wrap_tmux = true } },
  integrations = { companion = false, review = false },
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
  assert(type(value.panel.width) == "number" and value.panel.width >= 1 and value.panel.width % 1 == 0,
    "agent_workbench.panel.width must be a positive integer")
  assert(type(value.terminal.provider) == "table" or value.terminal.provider == "native" or value.terminal.provider == "snacks",
    "agent_workbench.terminal.provider must be native, snacks or a provider table")
  value.review = vim.tbl_deep_extend("force", vim.deepcopy(require("agent_workbench.review.defaults")), value.review or {})
  effective = value
end

function M.get() return vim.deepcopy(effective or defaults) end
function M.callback(name) return (effective or defaults).callbacks[name] end

return M
