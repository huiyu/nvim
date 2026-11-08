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
  { "git",     "version control, gitsigns, snacks pickers",            true },
  { "rg",      "ripgrep — snacks grep/search",                         true },
  { "fd",      "snacks file finding, venv-selector",                   false },
  { "node",    "AI ACP adapters, claudecode, markdown-preview, JS run", false },
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
-- when an update lands, as plugin/ui/treesitter.lua notes for the Nvim floor.
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
    local source, origin = require("util.input_method").default_source()
    if source then
      health.ok(("Normal-mode source is %s (%s)"):format(source, origin))
    else
      health.warn("Normal-mode input source could not be detected",
        { "Set NVIM_ENGLISH_INPUT_SOURCE to a macOS input-source ID" })
    end
  end

  local ai = require("ai.config")
  health.start("config: AI provider")
  local function moved(now, startup) return now ~= startup and (" (started as %s)"):format(startup) or "" end
  health.ok(("%s active (provider=%s%s), :AI provider switches it")
    :format(ai.label, ai.provider, moved(ai.provider, ai.startup.provider)))
  health.ok(("HTTP key profile %s (%s%s), :AI key switches it")
    :format(ai.key.label, ai.key_setting(), moved(ai.key_setting(), ai.startup.key)))

  -- Both providers, because either can become active with :AI. Only the
  -- active one's absence is an error: the other is unavailable, not broken.
  for _, name in ipairs(ai.names()) do
    local provider = ai.providers[name]
    local report = name == ai.provider and health.error or health.warn
    local command = provider.native.command
    if vim.fn.executable(command) == 1 then
      health.ok(("%s found — %s native agent available"):format(command, provider.label))
    else
      report(("%s not found — %s native agent unavailable"):format(command, provider.label))
    end
    local acp = provider.codecompanion.acp_command
    if vim.fn.executable(acp) == 1 then
      health.ok(("%s found — CodeCompanion Chat can use %s over ACP"):format(acp, provider.label))
    else
      report(("%s not found — CodeCompanion ACP Chat with %s unavailable"):format(acp, provider.label))
    end
  end

  -- The agents' ctrl+g ("edit this prompt in $EDITOR") is pointed at this
  -- wrapper. A non-executable one is not fatal -- ctrl+g falls back to starting
  -- a nested nvim inside the :terminal -- but that failure is silent, so it is
  -- worth surfacing here rather than leaving it to be discovered mid-prompt.
  local wrapper = require("ai.editor").wrapper()
  if vim.fn.executable(wrapper) == 1 then
    health.ok("agent-editor wrapper executable — ctrl+g edits the TUI prompt in this Nvim")
  else
    health.warn(("%s not executable — ctrl+g will open a nested nvim instead"):format(wrapper),
      { "chmod +x " .. wrapper })
  end

  local function is_set(var) return vim.env[var] ~= nil and vim.env[var] ~= "" end
  for _, name in ipairs(ai.key_names()) do
    local var = ai.key_profiles[name].api_key
    if is_set(var) then
      health.ok(("%s found — key profile %s can run HTTP inline/command prompts"):format(var, name))
    elseif name == ai.key.name then
      health.warn(("%s not set — ACP Chat works, but HTTP inline/command prompts do not"):format(var),
        { "See README.md, API keys" })
    else
      health.info(("%s not set — key profile %s unavailable until it is"):format(var, name))
    end
  end

  -- An agent's own variable outranks its subscription login, so an export
  -- meant for something else silently moves the native terminal and ACP Chat
  -- onto API billing. Both are checked: either agent can be started from here.
  for _, name in ipairs(ai.names()) do
    local provider = ai.providers[name]
    local cli_key = provider.cli_api_key
    if is_set(cli_key) then
      health.warn(("%s is set — %s started from this Nvim can bill the API instead of the subscription")
        :format(cli_key, provider.label), { "Unset it unless API billing is intended; Nvim reads NVIM_* keys" })
    else
      health.ok(("%s not set — %s uses its subscription login"):format(cli_key, provider.label))
    end
  end

  -- Independent of the provider above: ghost text always comes from the local
  -- server that util.llama starts on the first Insert.
  local llama = require("util.llama")
  health.start("config: inline completion")
  if vim.fn.executable(llama.config.server) ~= 1 then
    health.warn("llama-server not found — no AI ghost text", { "brew install llama.cpp" })
  else
    health.ok("llama-server found — started on the first Insert, shared by every Nvim")
    -- --offline means a missing model is a failed start, not a download.
    -- Resolved the way llama.cpp does, where an empty variable counts as unset.
    local function env(name)
      local value = vim.env[name]
      return value ~= "" and value or nil
    end
    local cache = env("HF_HUB_CACHE") or env("HUGGINGFACE_HUB_CACHE") or ((env("HF_HOME")
      or (env("XDG_CACHE_HOME") or (vim.uv.os_homedir() .. "/.cache")) .. "/huggingface") .. "/hub")
    local snapshots = ("%s/models--%s/snapshots"):format(cache, (llama.config.model:gsub("/", "--")))
    if #vim.fn.glob(snapshots .. "/*/*.gguf", false, true) > 0 then
      health.ok(("%s is in %s"):format(llama.config.model, cache))
    else
      health.warn(("%s is not in %s; the server starts --offline and cannot fetch it"):format(llama.config.model, cache),
        { "Download it once (~8 GB): llama-server --fim-qwen-7b-default, then Ctrl-C once it is listening" })
    end
    local answer = vim.fn.executable("curl") == 1
      and vim.system({ "curl", "-sf", "-o", "/dev/null", "--max-time", "1", llama.url("/health") }):wait()
    if answer and answer.code == 0 then
      health.ok("server answering at " .. llama.url(""))
    elseif llama.failed() then
      health.warn(("the server failed to start in this Nvim and is not retried; see %s"):format(llama.log()),
        { "Fix what the log reports, then restart Nvim" })
    else
      health.info(("server not running (it starts on the next Insert); last log: %s"):format(llama.log()))
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
