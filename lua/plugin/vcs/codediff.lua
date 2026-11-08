-- CodeDiff (esmuellert/codediff.nvim): the diff views behind <leader>g.
--
-- This file declares the plugin and its <leader>g entry points. Everything
-- that reaches into CodeDiff's internals -- the panel keys, the `;`/`s`
-- blocks, the tab labels, the git runner patch -- lives in
-- lua/util/codediff.lua, the one module allowed to.

--- Run git in `cwd`. Returns the output lines, or nil and git's first stderr
--- line -- "fatal: not a git repository ..." -- when it refused. `vim.fn.system`
--- folded that stderr into the output, where it then passed for a ref name.
---@param cwd string
---@return string[]?, string?
local function git(cwd, ...)
  if vim.fn.isdirectory(cwd) == 0 then return nil, "no such directory: " .. cwd end
  local result = vim.system({ "git", ... }, { text = true, cwd = cwd }):wait()
  if result.code ~= 0 then
    local reason = vim.split(result.stderr or "", "\n", { trimempty = true })[1]
    return nil, reason or ("git exited with " .. result.code)
  end
  return vim.split(result.stdout or "", "\n", { trimempty = true })
end

--- The repository CodeDiff picks when it is given no -C: the current buffer's
--- file, else the working directory (resolve_working_root in codediff's
--- commands/parse.lua). Checking the same one is what keeps a refusal here
--- and the view CodeDiff then opens about the same repository.
---@return string? root, string? reason
local function repo_root()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and not name:match("^%w+://") then
    local dir = vim.fn.isdirectory(name) == 1 and name or vim.fn.fnamemodify(name, ":h")
    local top = git(dir, "rev-parse", "--show-toplevel")
    if top then return top[1] end
  end
  local top, reason = git(vim.fn.getcwd(), "rev-parse", "--show-toplevel")
  if not top then return nil, reason end
  return top[1]
end

local function warn(what, reason)
  vim.notify(what .. ": " .. reason, vim.log.levels.WARN)
end

--- What <leader>gH/<leader>gV list, from the setting util.codediff applies:
--- `:CodeDiff history` without a range lists the newest non-merge commits,
--- 100 of them unless vim.g.ai_review.history_limit says otherwise. Read when
--- this spec is evaluated, so set it before lua/bootstrap.lua runs.
local function history_desc(what)
  local limit = require("ai.review.config").get().history_limit
  return ("%s (%s, no merges)"):format(what, limit and ("recent " .. limit) or "all")
end

local function diff_view()
  local root, reason = repo_root()
  if not root then return warn("Diff view", reason) end
  -- CodeDiff refuses a clean tree with its own "No changes to show" (#582);
  -- say why here instead. --no-optional-locks: a plain status rewrites
  -- .git/index.
  local status = git(root, "--no-optional-locks", "status", "--porcelain", "-z", "-uall")
  if status and #status == 0 then
    vim.notify("Diff view: the working tree is clean", vim.log.levels.INFO)
    return
  end
  -- No -C: CodeDiff then focuses the current file in its explorer.
  require("util.codediff").open({ args = {}, label = "index/HEAD ↔ working tree" })
end

local function diff_main()
  local root, reason = repo_root()
  if not root then return warn("Diff against main branch", reason) end
  -- Detect main branch: check for main, then master, fallback to HEAD
  local main = git(root, "rev-parse", "--verify", "--quiet", "main") and "main"
    or git(root, "rev-parse", "--verify", "--quiet", "master") and "master"
    or "HEAD"
  -- Against the working tree, not the merge base.
  require("util.codediff").open({ root = root, args = { main }, label = main .. " → working tree" })
end

local function diff_ref()
  local root, reason = repo_root()
  if not root then return warn("Diff against commit/branch", reason) end
  -- Fuzzy pick a git ref (branches, tags, recent commits) then diff against it.
  -- Goes through vim.ui.select, which snacks.picker (ui_select=true) intercepts.
  local branches, err = git(root, "branch", "--all", "--format=%(refname:short)")
  if not branches then return warn("Diff against commit/branch", err) end
  local refs = {}
  for _, b in ipairs(branches) do
    table.insert(refs, { ref = b, display = " " .. b })
  end
  for _, tag in ipairs(git(root, "tag", "--sort=-creatordate") or {}) do
    table.insert(refs, { ref = tag, display = " " .. tag })
  end
  for _, c in ipairs(git(root, "log", "--oneline", "-50") or {}) do
    table.insert(refs, { ref = c:match("^(%S+)"), display = " " .. c })
  end

  vim.ui.select(refs, {
    prompt = "Diff against",
    format_item = function(item) return item.display end,
  }, function(choice)
    if choice then
      require("util.codediff").open({ root = root, args = { choice.ref }, label = choice.ref .. " → working tree" })
    end
  end)
end

local function file_history()
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype ~= "" or name == "" or name:match("^%w+://") then
    return warn("File history", "the current buffer is not a file")
  end
  local root, reason = repo_root()
  if not root then return warn("File history", reason) end
  -- `%`, not the name: CodeDiff passes any other argument through expand(),
  -- which would read `$`, `*` or `#` in a file name as Vim syntax.
  require("util.codediff").open({
    args = { "history", "%" },
    label = "history · " .. (vim.fs.relpath(root, name) or vim.fs.basename(name)),
  })
end

local function repo_history()
  local root, reason = repo_root()
  if not root then return warn("Repo history", reason) end
  require("util.codediff").open({ args = { "history" }, label = "history · " .. vim.fs.basename(root) })
end

return {
  "esmuellert/codediff.nvim",
  -- v4.0.6. util.codediff reads internals this version has and checks it at
  -- setup; moving the pin means re-running tests/codediff_spec.lua first.
  commit = "09d9ebef2cc5a5c04db7a349cd6c61bdf84ecc8e",
  cmd = "CodeDiff",
  keys = {
    { "<leader>gv", diff_view,    desc = "Diff view",                  mode = "n" },
    {
      "<leader>gq",
      -- Not a bare :CodeDiff: that only closes when this tab has a view and
      -- opens a new one otherwise.
      function()
        if not require("util.codediff").close(vim.api.nvim_get_current_tabpage()) then
          vim.notify("No diff view in this tab", vim.log.levels.INFO)
        end
      end,
      desc = "Close diff view",
      mode = "n",
    },
    { "<leader>gm", diff_main,    desc = "Diff against main branch",   mode = "n" },
    { "<leader>gM", diff_ref,     desc = "Diff against commit/branch", mode = "n" },
    { "<leader>gV", file_history, desc = history_desc("File history"), mode = "n" },
    { "<leader>gH", repo_history, desc = history_desc("Repo history"), mode = "n" },
  },
  opts = {
    -- The explorer lists every untracked file, as `<leader>gv`'s clean-tree
    -- check counts them. Line stats stay off, as by default: with them on, a
    -- revision view would list its files through a second code path.
    explorer = { untracked = "all", line_stats = { enabled = false } },
    keymaps = {
      view = {
        -- q only closes from the explorer and history panels
        -- (util.codediff); in a diff pane it stays macro recording.
        quit = false,
        -- View actions join the comma menu: P/B as Diffview had them, I and
        -- z because `t` is flash and `gc` is the comment operator.
        toggle_explorer = "<localleader>B",
        focus_explorer = "<localleader>P",
        toggle_layout = "<localleader>I",
        toggle_compact = "<localleader>z",
        -- Index edits are ours (,u ,U ,X): upstream's stage the hunk against
        -- the revision rather than the index in a rev-vs-working-tree view.
        stage_hunk = false,
        unstage_hunk = false,
        discard_hunk = false,
        -- `-` is oil's parent directory; util.codediff gives it back to the
        -- status view's explorer only.
        toggle_stage = false,
        toggle_staged_view = false, -- gS is splitjoin
        align_move = false,         -- gm is a builtin
        -- Kept: ]c [c ]f [f do dp gf g? ih
      },
      -- Re-installed by util.codediff on the status view's explorer only:
      -- in a revision view the explorer's X deletes files that are merely
      -- untracked in the index.
      explorer = { stage_all = false, unstage_all = false, restore = false },
      -- Diffview's meanings, on ,g so ,c (codelens) stays immediate:
      -- o = ours, t = theirs, b = base, a = all; uppercase for the whole file.
      conflict = {
        accept_current = "<localleader>go",
        accept_incoming = "<localleader>gt",
        discard = "<localleader>gb",
        accept_both = "<localleader>ga",
        accept_all_current = "<localleader>gO",
        accept_all_incoming = "<localleader>gT",
        discard_all = "<localleader>gB",
        accept_all_both = "<localleader>gA",
      },
    },
  },
  config = function(_, opts)
    require("util.codediff").setup(opts, {
      history_limit = function() return require("ai.review.config").get().history_limit end,
    })
    -- util.codediff_actions installs the hunk keys (,u ,U ,X) on every pass.
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("codediff_actions", { clear = true }),
      pattern = "CodeDiffKeys",
      callback = function(ev) require("util.codediff_actions").attach(ev.data.tabpage) end,
    })
  end,
}
