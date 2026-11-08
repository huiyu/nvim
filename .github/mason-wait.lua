-- CI only (.github/workflows/tests.yml): wait for the Mason installs that
-- loading the LSP and DAP plugins started, until nothing has been installing
-- for 30 s, at most 15 minutes. On a fresh runner those installs otherwise ran
-- in the background during the spec suite, and whether a spec that needs a
-- package ran, skipped or failed depended on that race.
local registry = require("mason-registry")
-- vim.wait polls more often than its interval, so quiet is measured in time.
local busy_at = vim.uv.now()
local settled = vim.wait(15 * 60 * 1000, function()
  for _, pkg in ipairs(registry.get_all_packages()) do
    if pkg:is_installing() then
      busy_at = vim.uv.now()
      return false
    end
  end
  return vim.uv.now() - busy_at >= 30 * 1000
end, 1000)
local installed = registry.get_installed_package_names()
table.sort(installed)
print("mason: installed " .. table.concat(installed, " "))
if not settled then
  print("mason: still installing after 15 minutes")
  vim.cmd("cquit 1")
end
