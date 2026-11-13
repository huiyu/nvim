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

-- The review loop ---------------------------------------------------------
--
-- Read-only, apart from what util.baseline.list does itself (it drops refs
-- whose commit is gone, with a warning). Nothing below starts an agent or a
-- chat, or deletes a ref: the cleanup commands are printed for the user.

---A non-empty environment variable, or nil.
local function env_value(name)
  local value = vim.env[name]
  return (value ~= nil and value ~= "") and value or nil
end

local function plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

local function split_lines(s)
  return vim.split(s or "", "\n", { plain = true, trimempty = true })
end

-- git in `dir`, synchronously, with util.baseline's prefix: no optional locks
-- (a plain status rewrites .git/index) and none of the user's hooks.
-- GIT_NO_LAZY_FETCH keeps a missing object from becoming a fetch.
---@return string? stdout, string? err
local function git(dir, args)
  local ok, r = pcall(function()
    return vim.system(require("util.baseline").git_cmd(args), {
      cwd = dir,
      text = true,
      env = { GIT_NO_LAZY_FETCH = "1", LC_ALL = "C" },
    }):wait(10000)
  end)
  if not ok then return nil, tostring(r) end
  if r.code ~= 0 then return nil, vim.trim(r.stderr or "") end
  return r.stdout or ""
end

-- One section of the review checks: a check that raises is reported in its
-- own section instead of ending `:checkhealth config` there.
local function section(name, check)
  health.start(name)
  local ok, err = pcall(check)
  if not ok then health.error("this check failed: " .. tostring(err)) end
end

-- CodeDiff's install layout, as its README documents it: the plugin root holds
-- VERSION and the native library, named libvscode_diff_<VERSION>.<ext> by its
-- installer or libvscode_diff.<ext> by a local build.
local LIB_EXT = ({ OSX = "dylib", Windows = "dll" })[jit.os] or "so"
local EXE_SUFFIX = jit.os == "Windows" and ".exe" or ""

local function first_line(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local line = file:read("*l")
  file:close()
  return line and vim.trim(line) or nil
end

-- The library's own version, from CodeDiff's FFI wrapper (codediff.core.diff
-- get_version). Requiring that module loads codediff.nvim -- lazy's module
-- loader runs the spec's config -- and the library itself, which is why only
-- this check calls it, and only once the library file is known to exist. The
-- require would also download a library CodeDiff takes for stale; a health
-- check never downloads, so VSCODE_DIFF_NO_AUTO_INSTALL is held on for the
-- require and put back at once.
---@return string? version, string? err
local function library_version()
  local diff = package.loaded["codediff.core.diff"]
  if not diff then
    local saved = vim.env.VSCODE_DIFF_NO_AUTO_INSTALL
    vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = "1"
    local ok, mod = pcall(require, "codediff.core.diff")
    vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = saved
    if not ok then return nil, tostring(mod) end
    diff = mod
  end
  if type(diff) ~= "table" or type(diff.get_version) ~= "function" then
    return nil, "codediff.core.diff has no get_version"
  end
  local ok, version = pcall(diff.get_version)
  if not ok then return nil, tostring(version) end
  return tostring(version)
end

-- The watcher CodeDiff would start, found in its own order
-- (core/installer/watcher.lua ensure) after CODEDIFF_WATCHER_PATH: a local
-- build in the plugin root, the release it downloads there, then PATH. The
-- release it wants is that installer's VERSION, read once CodeDiff is loaded
-- (requiring it before would load the plugin); until then any downloaded
-- release counts.
local function find_watcher(plugin)
  local names = { "codediff-watcher" .. EXE_SUFFIX }
  local wanted
  if plugin._ and plugin._.loaded then
    local ok, installer = pcall(require, "codediff.core.installer.watcher")
    wanted = ok and type(installer) == "table" and type(installer.VERSION) == "string" and installer.VERSION or nil
  end
  if wanted then
    names[#names + 1] = ("codediff-watcher_%s%s"):format(wanted, EXE_SUFFIX)
  elseif vim.fn.isdirectory(plugin.dir) == 1 then
    for name in vim.fs.dir(plugin.dir) do
      if name:match("^codediff%-watcher_") then names[#names + 1] = name end
    end
  end
  for _, name in ipairs(names) do
    local path = plugin.dir .. "/" .. name
    if vim.fn.filereadable(path) == 1 then return path end
  end
  local on_path = vim.fn.exepath("codediff-watcher")
  return on_path ~= "" and on_path or nil
end

local function check_codediff()
  local ok, lazy = pcall(require, "lazy.core.config")
  local plugin = ok and type(lazy.plugins) == "table" and lazy.plugins["codediff.nvim"] or nil
  if not plugin or vim.fn.isdirectory(plugin.dir or "") == 0 then
    health.error("codediff.nvim is not installed — no <leader>g diff views and no review views", { ":Lazy install" })
    return
  end
  local dir = plugin.dir

  -- The same comparison util.codediff.setup makes before it patches anything.
  local version = first_line(dir .. "/VERSION")
  local pinned = require("util.codediff").VERSION
  if version == pinned then
    health.ok(("codediff.nvim %s, the release util.codediff is written against — its patches are on"):format(version))
  else
    health.warn(("codediff.nvim %s is not the %s util.codediff is written against — "
      .. "its path fix, revision listing and history limit are off"):format(version or "(no VERSION file)", pinned), {
        ":Lazy restore codediff.nvim goes back to the commit in lazy-lock.json",
        "For an intended update: run tests/codediff_spec.lua, then raise VERSION in lua/util/codediff.lua",
      })
  end

  local no_auto = env_value("VSCODE_DIFF_NO_AUTO_INSTALL")
  local versioned = ("libvscode_diff_%s.%s"):format(version or "<version>", LIB_EXT)
  local lib
  -- CodeDiff loads the versioned file first and a local build after it.
  for _, name in ipairs({ versioned, "libvscode_diff." .. LIB_EXT }) do
    if vim.fn.filereadable(dir .. "/" .. name) == 1 then
      lib = name
      break
    end
  end
  if not lib then
    health.warn(("native diff library %s is missing from %s — no diff view opens until it is there")
      :format(versioned, dir), {
      no_auto and ":CodeDiff install downloads it (VSCODE_DIFF_NO_AUTO_INSTALL stops the download on first use)"
        or "CodeDiff downloads it on first use (curl or wget, github.com); :CodeDiff install does it now",
      "See docs/DIAGNOSTICS.md",
    })
  else
    local got, err = library_version()
    if not got then
      health.error(("native diff library %s does not load — CodeDiff cannot diff: %s"):format(lib, err), {
        ":CodeDiff install! reinstalls it",
        jit.os == "Linux" and "On Linux it also needs libgomp.so.1; see CodeDiff's README" or nil,
      })
    elseif version and got ~= version then
      health.warn(("native diff library %s reports %s, codediff.nvim is %s"):format(lib, got, version),
        { ":CodeDiff install! fetches the matching one" })
    else
      health.ok(("native diff library %s loads (%s)"):format(got, lib))
    end
  end
  if no_auto then
    health.info(("VSCODE_DIFF_NO_AUTO_INSTALL=%s — CodeDiff never downloads its library on its own; "
      .. ":CodeDiff install still does"):format(no_auto))
  end

  -- Only "1" counts here: the installer compares the value, where the library
  -- loader above takes any non-empty value.
  local watcher_no_auto = env_value("CODEDIFF_WATCHER_NO_AUTO_INSTALL")
  if watcher_no_auto == "1" then
    health.info("CODEDIFF_WATCHER_NO_AUTO_INSTALL=1 — CodeDiff never downloads its file watcher")
  elseif watcher_no_auto then
    health.info(("CODEDIFF_WATCHER_NO_AUTO_INSTALL=%s has no effect — only 1 stops the watcher download")
      :format(watcher_no_auto))
  end

  local polling = "CodeDiff polls the repository every 500 ms instead"
  local override = env_value("CODEDIFF_WATCHER_PATH")
  if override and vim.fn.executable(override) == 1 then
    health.ok(("file watcher %s (CODEDIFF_WATCHER_PATH) — views refresh on file events"):format(override))
    return
  end
  -- CodeDiff takes any readable override and only fails when it starts it;
  -- one it cannot read, it passes over.
  if override and vim.fn.filereadable(override) == 1 then
    health.warn(("CODEDIFF_WATCHER_PATH=%s is not executable — %s"):format(override, polling),
      { "chmod +x " .. vim.fn.shellescape(override) })
    return
  end
  if override then
    health.warn(("CODEDIFF_WATCHER_PATH=%s does not exist — CodeDiff ignores it"):format(override))
  end
  local watcher = find_watcher(plugin)
  if watcher then
    health.ok(("file watcher %s — views refresh on file events"):format(watcher))
  else
    health.warn("no CodeDiff file watcher — " .. polling, {
      watcher_no_auto == "1"
          and "CODEDIFF_WATCHER_NO_AUTO_INSTALL=1 keeps CodeDiff from downloading it: unset it and open a diff view"
        or "CodeDiff downloads it on the first diff view (curl or wget, github.com)",
      "Or put codediff-watcher on PATH, or point CODEDIFF_WATCHER_PATH at one",
    })
  end
end

-- util.baseline hands `git add` its pathspecs on stdin (--pathspec-from-file),
-- which git learned in 2.26; with an older git every snapshot fails. Nothing
-- else in the review loop or the diff views needs a newer one.
local GIT_MIN = "2.26"

local function check_git()
  if vim.fn.executable("git") ~= 1 then
    health.error("git not found — no diff views and no review baselines")
    return
  end
  local out = vim.system({ "git", "--version" }, { text = true }):wait(5000)
  local version = vim.version.parse(out.stdout or "")
  if version and vim.version.ge(version, GIT_MIN) then
    health.ok(("git %s — review baselines need %s or later"):format(tostring(version), GIT_MIN))
  else
    health.error(("git %s — review baselines need %s or later (git add --pathspec-from-file); every snapshot fails")
      :format(version and tostring(version) or "(unknown version)", GIT_MIN),
      { "Install a newer git (brew install git)" })
  end
end

-- The Codex `-c` value with every TOML basic string replaced by `$`, and the
-- strings it held, decoded, in order: its shape can then be compared whole.
local TOML_UNESCAPE = { ['"'] = '"', ["\\"] = "\\", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

---@return string? shape, string[] strings
local function toml_strings(s)
  local shape, strings, i = {}, {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c ~= '"' then
      shape[#shape + 1], i = c, i + 1
    else
      local buf, j = {}, i + 1
      while true do
        local ch = s:sub(j, j)
        if ch == "" then return nil, {} end
        if ch == '"' then break end
        if ch == "\\" then
          local e = s:sub(j + 1, j + 1)
          local hex = e == "u" and s:sub(j + 2, j + 5):match("^%x%x%x%x$")
          if TOML_UNESCAPE[e] then
            buf[#buf + 1], j = TOML_UNESCAPE[e], j + 2
          elseif hex then
            buf[#buf + 1], j = vim.fn.nr2char(tonumber(hex, 16)), j + 6
          else
            return nil, {}
          end
        else
          buf[#buf + 1], j = ch, j + 1
        end
      end
      strings[#strings + 1] = table.concat(buf)
      shape[#shape + 1], i = "$", j + 1
    end
  end
  return table.concat(shape), strings
end

local CODEX_SHAPE =
  "^hooks={UserPromptSubmit=%[{hooks=%[{type=%$,command=%$,timeout=(%d+)}%]}%],state={%$={trusted_hash=%$}}}$"

-- Each sources.* switch, with the prompts it stops opening rounds.
local SOURCES = {
  { "claude", "native Claude" },
  { "codex", "native Codex" },
  { "codecompanion_acp", "ACP chats (<leader>an)" },
  { "codecompanion_http", "API chats (<leader>an)" },
}

-- Static checks only: the strings ai.review.hook generates are parsed and
-- compared with what scripts/agent-hook and each CLI expect. No agent runs,
-- so whether a CLI then accepts them is left to the hints at the end.
local function check_hooks()
  local hook = require("ai.review.hook")
  local review = require("ai.review.config").get()
  local wait = review.hook_wait_ms
  local script = hook.script()
  local no_round = "the native agents' prompt hooks cannot run, so their prompts open no review round"
  if vim.fn.executable(script) == 1 then
    health.ok("agent-hook executable — the native agents' prompt hooks run it")
  elseif vim.uv.fs_stat(script) then
    health.warn(("%s is not executable — %s"):format(script, no_round), { "chmod +x " .. vim.fn.shellescape(script) })
  else
    health.warn(("%s is missing — %s"):format(script, no_round),
      { "It belongs to this config: restore it from the repository" })
  end
  if vim.fn.executable("nvim") ~= 1 then
    health.warn("nvim is not on PATH — agent-hook calls back into this Nvim with `nvim --server`, "
      .. "so native prompts open no review round", { "Start Nvim with its directory on PATH" })
  end

  local decoded, settings = pcall(vim.json.decode, hook.claude_settings())
  local function claude_handler(event)
    return decoded and type(settings) == "table" and vim.tbl_get(settings, "hooks", event, 1, "hooks", 1) or nil
  end
  local function runs_script(handler, event)
    return type(handler) == "table" and handler.type == "command" and handler.command == script
      and vim.deep_equal(handler.args, { "claude", event, tostring(wait) })
  end
  local submit, session = claude_handler("UserPromptSubmit"), claude_handler("SessionStart")
  if not decoded then
    health.error("Claude's --settings value is not valid JSON: " .. tostring(settings),
      { "tests/agent_hook_spec.lua pins it" })
  elseif runs_script(submit, "submit") and type(submit.timeout) == "number" and submit.timeout * 1000 > wait
    and runs_script(session, "session") and session.async == true then
    health.ok(("Claude --settings is valid: UserPromptSubmit waits up to %d ms (hook timeout %d s), "
      .. "SessionStart runs async"):format(wait, submit.timeout))
  else
    health.error("Claude's --settings value parses but is not the agent-hook pair it should carry — "
      .. "native Claude prompts open no review round", { "tests/agent_hook_spec.lua pins it" })
  end

  -- Codex runs its hook through a shell, so the command is one string.
  local shape, strings = toml_strings(hook.codex_override())
  local timeout = shape and tonumber(shape:match(CODEX_SHAPE))
  local command = vim.fn.shellescape(script) .. " codex submit " .. wait
  if not (timeout and strings[1] == "command" and strings[2] == command and strings[3] == hook.CODEX_TRUST_KEY) then
    health.error("Codex's -c hooks= value is not the agent-hook entry it should carry — "
      .. "native Codex prompts open no review round", { "tests/agent_hook_spec.lua pins it" })
  else
    local want = hook.codex_trust_hash("user_prompt_submit", command, timeout)
    if strings[4] == want and want:match("^sha256:" .. ("%x"):rep(64) .. "$") then
      health.ok(("Codex -c hooks= is valid: UserPromptSubmit waits up to %d ms (hook timeout %d s), "
        .. "its trusted_hash matches"):format(wait, timeout))
    else
      health.error(("Codex's trusted_hash %s is not %s, the hash of the command it carries — "
        .. "Codex would not run the hook without a review"):format(tostring(strings[4]), want),
        { "tests/agent_hook_spec.lua pins it" })
    end
  end

  for _, source in ipairs(SOURCES) do
    if review.sources[source[1]] == false then
      health.info(("sources.%s = false — %s prompts open no review round"):format(source[1], source[2]))
    end
  end
  health.info("Not checked here: Claude runs no hook under --bare, with disableAllHooks or allowManagedHooksOnly "
    .. "in managed settings, or in a folder it has not trusted")
  health.info("Not checked here: whether a newer Codex still accepts that hash. "
    .. "Codex's /hooks lists ours under Session flags; Claude's /hooks leaves out --settings hooks, "
    .. "so there <leader>aV naming a Claude session shows SessionStart arrived")
end

local function wtid_of(gitdir)
  return vim.fn.sha256(gitdir):sub(1, 12)
end

-- `cd <root> && git for-each-ref ... | git update-ref --stdin`: deletes every
-- ref under the given prefixes, in the repository at `root`.
local function delete_refs_command(root, prefixes)
  local quoted = vim.tbl_map(vim.fn.shellescape, prefixes)
  return ("cd %s && git for-each-ref --format='delete %%(refname)' %s | git update-ref --stdin")
    :format(vim.fn.shellescape(root), table.concat(quoted, " "))
end

-- Refs under refs/nvim-review/ whose worktree id names no worktree of this
-- repository any more (`git worktree remove`, or a moved repository). They
-- keep their commits from gc and nothing deletes them on its own.
local function check_orphans(loc, namespace)
  local common, err = git(loc.toplevel, { "rev-parse", "--git-common-dir" })
  local refs, refs_err = git(loc.toplevel, { "for-each-ref", "--format=%(refname)%00%(objectname)", namespace .. "/" })
  if not (common and refs) then
    health.warn("could not look for baselines of removed worktrees: " .. tostring(err or refs_err))
    return
  end
  -- Every worktree's gitdir, hashed the way util.baseline.locate names it:
  -- the common dir is the main worktree's, linked ones live under worktrees/.
  common = vim.trim(common)
  if common:sub(1, 1) ~= "/" then common = loc.toplevel .. "/" .. common end
  common = vim.uv.fs_realpath(common) or common
  local alive = { [loc.wtid] = true, [wtid_of(common)] = true }
  if vim.fn.isdirectory(common .. "/worktrees") == 1 then
    for name, kind in vim.fs.dir(common .. "/worktrees") do
      local gitdir = common .. "/worktrees/" .. name
      if kind == "directory" then alive[wtid_of(vim.uv.fs_realpath(gitdir) or gitdir)] = true end
    end
  end

  local orphans, order = {}, {}
  for _, line in ipairs(split_lines(refs)) do
    local name, sha = line:match("^(.-)%z(%x+)$")
    local wtid, kind = (name or ""):match("^" .. vim.pesc(namespace) .. "/([^/]+)/([^/]+)/")
    if wtid and not alive[wtid] then
      local o = orphans[wtid]
      if not o then
        o = { refs = 0, shas = {} }
        orphans[wtid], order[#order + 1] = o, wtid
      end
      o.refs = o.refs + 1
      -- Rounds carry a Root trailer and saved baselines do not: rounds first.
      table.insert(o.shas, kind == "round" and 1 or #o.shas + 1, sha)
    end
  end
  if #order == 0 then
    health.ok("no baseline refs of removed worktrees")
    return
  end
  table.sort(order)
  local described, prefixes, total = {}, {}, 0
  for _, wtid in ipairs(order) do
    local o = orphans[wtid]
    total = total + o.refs
    local root
    for i = 1, math.min(#o.shas, 3) do
      local body = git(loc.toplevel, { "cat-file", "commit", o.shas[i] })
      root = body and body:match("\nRoot: ([^\n]+)")
      if root then break end
    end
    described[#described + 1] = ("%s (%s%s)"):format(wtid, plural(o.refs, "ref"), root and (", Root " .. root) or "")
    prefixes[#prefixes + 1] = ("%s/%s/"):format(namespace, wtid)
  end
  health.warn(("%s of worktrees that no longer exist: %s — they keep their commits from gc, "
    .. "and nothing deletes them on its own"):format(plural(total, "baseline ref"), table.concat(described, "; ")),
    { "To delete them (from any worktree of this repository):", delete_refs_command(loc.toplevel, prefixes) })
end

-- Counted for the worktree that contains the cwd: baselines and drafts are
-- per worktree, and :checkhealth's own buffer has no file to go by.
local function check_baselines()
  local cwd = vim.fn.getcwd()
  if vim.fn.executable("git") ~= 1 then
    health.info("git not found — no baselines to count")
    return
  end
  local B = require("util.baseline")
  local loc, err = B.locate(cwd)
  if not loc then
    if err:find("not a git repository", 1, true) then
      health.info(("%s is not in a Git worktree — baselines belong to one, so there is nothing to count here")
        :format(cwd))
    elseif err:find("^bare repository") then
      health.info(err)
    elseif err:find("is set in Nvim's environment", 1, true) then
      health.warn(err, { "Start Nvim without GIT_DIR and GIT_WORK_TREE" })
    else
      health.warn(err)
    end
    return
  end

  local retention = require("ai.review.config").get().retention
  local done, entries, list_err = false, nil, nil
  B.list(loc.toplevel, function(found, e) entries, list_err, done = found, e, true end)
  vim.wait(10000, function() return done end, 20)
  if not done or list_err then
    health.warn(("could not list the baselines of %s: %s"):format(loc.toplevel, list_err or "timed out"))
  else
    local count = { round = 0, saved = 0 }
    for _, entry in ipairs(entries) do count[entry.kind] = (count[entry.kind] or 0) + 1 end
    health.ok(("%d round and %d saved baselines for %s (worktree id %s); retention keeps the newest %d and %d")
      :format(count.round, count.saved, loc.toplevel, loc.wtid,
        retention.rounds, retention.saved))
  end

  check_orphans(loc, B.NAMESPACE)

  -- CodeCompanion's own code_review (turned off in
  -- lua/plugins/ai/codecompanion.lua) kept its baselines as per-worktree refs.
  local cc, cc_err = git(loc.toplevel, { "for-each-ref", "--format=%(refname)", "refs/worktree/codecompanion/" })
  local cc_refs = split_lines(cc)
  if not cc then
    health.warn("could not look for CodeCompanion's refs: " .. tostring(cc_err))
  elseif #cc_refs == 0 then
    health.ok("no refs/worktree/codecompanion/* left by CodeCompanion's code_review")
  else
    health.warn(("%s under refs/worktree/codecompanion/ in this worktree, left by CodeCompanion's code_review, "
      .. "which this config turns off; nothing reads them"):format(plural(#cc_refs, "ref")),
      { "To delete them:", delete_refs_command(loc.toplevel, { "refs/worktree/codecompanion/" }) })
  end

  -- A draft holds feedback only while it is a non-empty file: delivering it,
  -- or deleting every entry, leaves it empty (lua/ai/review/feedback.lua), and
  -- only a non-empty one spares its round from retention (rounds._exempt).
  -- <id>.last-sent.md is the copy of the last delivery, not a draft.
  local dir = vim.fs.dirname(require("ai.review.rounds").draft_path(loc.toplevel, "unowned"))
  local drafts, sent, conflicts = 0, 0, 0
  if vim.fn.isdirectory(dir) == 1 then
    for name, kind in vim.fs.dir(dir) do
      if kind == "file" and name:match("%.conflict%-?%d*%.md$") then
        conflicts = conflicts + 1
      elseif kind == "file" and name:match("%.last%-sent%.md$") then
        sent = sent + 1
      elseif kind == "file" and name:match("%.md$") then
        local stat = vim.uv.fs_stat(dir .. "/" .. name)
        if stat and stat.size > 0 then drafts = drafts + 1 end
      end
    end
  end
  local copies = sent == 0 and "" or (", %d last-sent %s"):format(sent, sent == 1 and "copy" or "copies")
  health.info(("feedback drafts for this worktree live in %s: %s with feedback%s%s"):format(dir,
    plural(drafts, "draft"), copies, conflicts > 0 and (", " .. plural(conflicts, "conflict file")) or ""))
end

-- Every setting with the value in effect, and where it comes from
-- (lua/ai/review/config.lua holds the defaults and their domains).
local function check_review_settings()
  local config = require("ai.review.config")
  local effective, from_user = config.get(), config.overrides()

  -- A non-empty table that is not a list is a group of settings.
  local function is_group(value)
    return type(value) == "table" and next(value) ~= nil and not vim.islist(value)
  end
  local function leaves(node, prefix, out)
    local keys = vim.tbl_keys(node)
    table.sort(keys)
    for _, key in ipairs(keys) do
      local path = prefix == "" and key or prefix .. "." .. key
      if is_group(node[key]) then leaves(node[key], path, out) else out[#out + 1] = path end
    end
    return out
  end
  local function at(node, path)
    for part in path:gmatch("[^.]+") do
      if type(node) ~= "table" then return nil end
      node = node[part]
    end
    return node
  end

  local defaults = config.defaults()
  for _, path in ipairs(leaves(defaults, "", {})) do
    health.info(("%s = %s (%s)"):format(path, vim.inspect(at(effective, path)),
      from_user[path] and "vim.g.ai_review" or "default"))
  end

  -- What vim.g.ai_review asked for and did not get: config.lua warned about
  -- each one when it fell back.
  local user = vim.g.ai_review
  if user ~= nil and type(user) ~= "table" then
    health.warn(("vim.g.ai_review is a %s, not a table — every setting is its default"):format(type(user)))
    return
  end
  if user == nil then return end
  local rejected, trimmed = {}, {}
  local function compare(node, schema, prefix)
    for key, value in pairs(node) do
      local path = prefix == "" and tostring(key) or prefix .. "." .. tostring(key)
      local default = type(schema) == "table" and schema[key] or nil
      if is_group(default) and type(value) == "table" then
        compare(value, default, path)
      elseif not from_user[path] then
        rejected[#rejected + 1] = "vim.g.ai_review." .. path
      elseif type(value) == "table" and #value ~= #(at(effective, path) or {}) then
        trimmed[#trimmed + 1] = "vim.g.ai_review." .. path
      end
    end
  end
  compare(user, defaults, "")
  table.sort(rejected)
  table.sort(trimmed)
  local why = { "An unknown key or a value outside the setting's domain: the \"AI review\" warning names each problem" }
  if #rejected > 0 then
    health.warn("not applied, the default is used instead: " .. table.concat(rejected, ", "), why)
  end
  if #trimmed > 0 then
    health.warn("applied without the entries that are not valid: " .. table.concat(trimmed, ", "), why)
  end
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
  health.start("config: AI backends")
  health.info("Providers, in the order of lua/ai/config.lua; <leader>an lists every available one")
  health.ok(("HTTP key profile %s (%s), :AI key switches it"):format(ai.key.label, ai.key_setting()))

  -- Every part each provider offers. A missing one is a warning: the picker
  -- leaves it out and the rest still work. Only nothing at all is an error.
  local any, label = false, {}
  for _, provider in ipairs(ai.providers) do label[provider.name] = provider.label end
  for _, b in ipairs(ai.backends()) do
    local name = label[b.provider]
    if b.kind == "native" then
      if b.available then
        any = true
        health.ok(("%s found — %s native agent available"):format(b.command, name))
      else
        health.warn(("%s not found — %s native agent unavailable"):format(b.command, name))
      end
    elseif b.kind == "acp" then
      if b.available then
        any = true
        health.ok(("%s found — <leader>an can start %s over ACP"):format(b.command, name))
      else
        health.warn(("%s not found — no %s chat over ACP"):format(b.command, name))
      end
    end -- API chats: the key checks below
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
      any = true
      health.ok(("%s found — key profile %s can run API chats and inline/command prompts"):format(var, name))
    elseif name == ai.key.name then
      health.warn(("%s not set — native and ACP chats work; inline edits refuse until it is set"):format(var),
        { "See README.md, API keys" })
    else
      health.info(("%s not set — no %s API chat until it is"):format(var, name))
    end
  end

  if not any then
    health.error("No AI backend is available: no agent CLI, ACP bridge or API key found",
      { "Install claude or codex, or set an NVIM_* API key; see README.md" })
  end

  -- An agent's own variable outranks its subscription login, so an export
  -- meant for something else silently moves the native terminal and ACP chat
  -- onto API billing. Every provider is checked: any of them can be started.
  for _, provider in ipairs(ai.providers) do
    local cli_key = provider.cli_api_key
    if cli_key and is_set(cli_key) then
      health.warn(("%s is set — %s started from this Nvim can bill the API instead of the subscription")
        :format(cli_key, provider.label), { "Unset it unless API billing is intended; Nvim reads NVIM_* keys" })
    elseif cli_key then
      health.ok(("%s not set — %s uses its subscription login"):format(cli_key, provider.label))
    end
  end

  -- Independent of the backends above: ghost text always comes from the local
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

  -- The diff views and the agent review loop on top of them.
  section("config: CodeDiff", check_codediff)
  section("config: git", check_git)
  section("config: review hooks", check_hooks)
  section("config: review baselines", check_baselines)
  section("config: review settings (vim.g.ai_review)", check_review_settings)

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
