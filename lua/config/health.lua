-- Health checks for THIS configuration. Run with `:checkhealth config`.
--
-- Covers config-specific diagnostics that Neovim's built-in `:checkhealth` does
-- not: external CLI dependencies, key Mason packages, and the Neovim version
-- floor. See docs/DIAGNOSTICS.md for the full diagnostic workflow.
local M = {}

local health = vim.health

-- External CLI tools the config relies on (not managed by Mason).
-- { executable, what needs it, required }
local executables = {
  { "git",     "version control, gitsigns, snacks pickers", true },
  { "rg",      "ripgrep — snacks grep/search",              true },
  { "fd",      "snacks file finding, venv-selector",        false },
  { "node",    "AI ACP adapters, claudecode, markdown-preview, JS run", false },
  { "go",      "go toolchain, <leader>cx for Go",           false },
  { "python3", "debugpy venv, <leader>cx for Python",       false },
  { "cc",      "<leader>cx compile & run for C",            false },
  { "lazygit", "<leader>gg git UI",                          false },
  { "gh",      "<leader>gh GitHub pickers and status",       false },
}

-- Mason packages worth surfacing (Mason installs lazily, so absence is info).
local mason_packages = { "lua-language-server", "vtsls", "gopls", "prettier" }

local function installed_mason_names()
  local ok, mr = pcall(require, "mason-registry")
  if not ok then
    return nil
  end
  if type(mr.get_installed_package_names) == "function" then
    return mr.get_installed_package_names()
  end
  local names = {}
  for _, p in ipairs(mr.get_installed_packages and mr.get_installed_packages() or {}) do
    names[#names + 1] = p.name
  end
  return names
end

function M.check()
  health.start("config: Neovim version")
  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim >= 0.11 required (config uses vim.lsp.config / vim.hl)")
  end

  health.start("config: external tools")
  for _, t in ipairs(executables) do
    local exe, why, required = t[1], t[2], t[3]
    if vim.fn.executable(exe) == 1 then
      health.ok(("%s found — %s"):format(exe, why))
    elseif required then
      health.error(("%s not found — needed for %s"):format(exe, why))
    else
      health.warn(("%s not found — %s unavailable"):format(exe, why))
    end
  end

  local ai = require("ai.config")
  health.start("config: AI provider")
  health.ok(("%s selected (provider=%s)"):format(ai.label, ai.provider))

  if vim.fn.executable(ai.native.command) == 1 then
    health.ok(("%s found — native coding agent available"):format(ai.native.command))
  else
    health.error(("%s not found — %s native agent unavailable"):format(ai.native.command, ai.label))
  end

  local acp_command = ai.codecompanion.acp_command
  if vim.fn.executable(acp_command) == 1 then
    health.ok(("%s found — CodeCompanion Chat uses %s over ACP"):format(acp_command, ai.label))
  else
    health.error(("%s not found — CodeCompanion ACP Chat unavailable"):format(acp_command))
  end

  local api_key = ai.codecompanion.api_key
  if vim.env[api_key] and vim.env[api_key] ~= "" then
    health.ok(("%s found — CodeCompanion HTTP inline/command prompts available"):format(api_key))
  else
    health.warn(("%s not set — ACP Chat works, but HTTP inline/command prompts do not"):format(api_key))
  end

  health.start("config: logs")
  local log_path = vim.lsp.log.get_filename()
  local stat = vim.uv.fs_stat(log_path)
  if stat and stat.size > 10 * 1024 * 1024 then
    health.warn(("LSP log is %.1f MiB: %s"):format(stat.size / 1024 / 1024, log_path))
  else
    health.ok("LSP log size is below 10 MiB")
  end

  health.start("config: mason packages")
  local names = installed_mason_names()
  if not names then
    health.warn("mason-registry not available yet (open a file to load Mason)")
  else
    local set = {}
    for _, n in ipairs(names) do
      set[n] = true
    end
    for _, pkg in ipairs(mason_packages) do
      if set[pkg] then
        health.ok(pkg .. " installed")
      else
        health.info(pkg .. " not installed yet (Mason installs on demand)")
      end
    end
  end
end

return M
