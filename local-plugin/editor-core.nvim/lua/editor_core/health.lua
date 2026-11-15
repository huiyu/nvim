-- Health checks for THIS configuration. Run with `:checkhealth config`.
--
-- Covers config-specific diagnostics that Neovim's built-in `:checkhealth` does
-- not: external CLI dependencies, key Mason packages, the Neovim version
-- floor, and what the review loop stands on (CodeDiff and its native library,
-- git, the agents' prompt hooks, this worktree's baselines, vim.g.ai_review).
-- See docs/DIAGNOSTICS.md for the full diagnostic workflow.
--
-- Nothing here runs at startup: this module is only required by
-- `:checkhealth`, and it is the one place that loads CodeDiff's native library
-- outside a diff view (see check_codediff).
local M = {}

local health = vim.health

-- External CLI tools the config relies on (not managed by Mason).
-- { executable, what needs it, required }
local executables = {
  { "git",     "version control, gitsigns, snacks pickers",            true },
  { "rg",      "ripgrep — snacks grep/search",                         true },
  { "fd",      "snacks file finding, venv-selector",                   false },
  { "node",    "AI ACP bridges, npm-based Mason servers, ,x runner and debugging for JS/TS", false },
  { "tmux",    "native AI TUI frame wrapper",                          false },
  { "go",      "go toolchain, ,x runner for Go",                       false },
  { "java",    "JDK 25+ runs jdtls; Java debugging",                   false },
  { "cargo",   "Rust binary and test debugging",                        false },
  { "dart",    "Dart debugging (or use a project FVM SDK)",             false },
  { "flutter", "Flutter debugging (or use a project FVM SDK)",          false },
  { "python3", "debugpy venv, ,x runner for Python",                    false },
  { "cc",      "Treesitter parser builds, ,x compile & run for C",      false },
  { "lazygit", "<leader>gg git UI",                                    false },
  { "curl",    "AI ghost-text requests and llama-server checks",       false },
  { "gh",      "<leader>G GitHub pickers and status",                  false },
}

-- Platform-gated tools, appended so `:checkhealth config` elsewhere does not
-- warn about something that platform could never use.
if vim.fn.has("macunix") == 1 then
  table.insert(executables,
    { "macism", "macOS input-source switching between Normal and input", false })
end

-- nvim-treesitter's main branch builds every parser with `tree-sitter build`,
-- so without this CLI no parser installs or updates, and every
-- `build = ":TSUpdate"` asks for a rebuild. The floor is nvim-treesitter's own
-- (README requirements, TREE_SITTER_MIN_VER in its health.lua); compare the two
-- when an update lands, as plugins/ui/treesitter.lua notes for the Nvim floor.
local TREE_SITTER_MIN = "0.26.1"

local function check_tree_sitter()
  local fix = { "brew install tree-sitter-cli (a package manager's build, not npm's)" }
  if vim.fn.executable("tree-sitter") ~= 1 then
    health.error("tree-sitter not found — nvim-treesitter cannot build parsers", fix)
    return
  end
  local out = vim.system({ "tree-sitter", "--version" }, { text = true }):wait(5000)
  local version = vim.version.parse(out.stdout or "")
  if version and vim.version.ge(version, TREE_SITTER_MIN) then
    health.ok(("tree-sitter %s found — nvim-treesitter builds parsers with it"):format(tostring(version)))
  else
    health.error(("tree-sitter %s found — nvim-treesitter needs %s or later")
      :format(version and tostring(version) or "(unknown version)", TREE_SITTER_MIN), fix)
  end
end

-- Mason packages worth surfacing (Mason installs lazily, so absence is info).
local mason_packages = { "lua-language-server", "vtsls", "gopls", "prettier",
  "jdtls", "java-debug-adapter", "java-test", "codelldb", "delve", "js-debug-adapter" }

local function installed_mason_names()
  local ok, mr = pcall(require, "mason-registry")
  if not ok then
    return nil
  end
  return mr.get_installed_package_names()
end

function M.check()
  health.start("config: Neovim version")
  if vim.fn.has("nvim-0.12.5") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim >= 0.12.5 required (refactoring.nvim's minimum; nvim-treesitter main needs 0.12)")
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
  check_tree_sitter()

  health.start("config: input method")
  if vim.fn.has("macunix") ~= 1 then
    health.info("automatic input-source switching is only enabled on macOS")
  else
    local source, origin = require("editor_core.input_method").default_source()
    if source then
      health.ok(("Normal-mode source is %s (%s)"):format(source, origin))
    else
      health.warn("Normal-mode input source could not be detected",
        { "Set NVIM_ENGLISH_INPUT_SOURCE to a macOS input-source ID" })
    end
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
    health.warn("mason.nvim is not installed (run :Lazy install)")
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
