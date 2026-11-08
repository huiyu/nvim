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

-- Picker items name one end of a comparison: { kind, rev?, label, display,
-- baseline? }. kind is "working", "index", "rev" (a baseline's sha, a
-- branch, a tag, a commit, a typed revision), "range" (a typed A...B or A...,
-- a whole comparison of its own) or "type" (the free-input entry).

--- Branches, tags and the 50 newest commits of `root`, as picker items.
---@return table[]?, string?
local function ref_items(root)
  local branches, err = git(root, "branch", "--all", "--format=%(refname:short)")
  if not branches then return nil, err end
  local items = {}
  for _, b in ipairs(branches) do
    items[#items + 1] = { kind = "rev", rev = b, label = b, display = " " .. b }
  end
  for _, tag in ipairs(git(root, "tag", "--sort=-creatordate") or {}) do
    items[#items + 1] = { kind = "rev", rev = tag, label = tag, display = " " .. tag }
  end
  for _, c in ipairs(git(root, "log", "--oneline", "-50") or {}) do
    local sha = c:match("^(%S+)")
    items[#items + 1] = { kind = "rev", rev = sha, label = sha, display = " " .. c }
  end
  return items
end

--- When a baseline was taken: the time today, the date and time before.
local function when(time)
  if os.date("%Y-%m-%d", time) == os.date("%Y-%m-%d") then return os.date("%H:%M:%S", time) end
  return os.date("%Y-%m-%d %H:%M", time)
end

--- The baselines of the worktree at `root` (util.baseline; this worktree's
--- only), newest first, as picker items: `cb(items)`. The vcs layer reads a
--- baseline's subject and sha, nothing else; what its trailers mean belongs
--- to ai.review. CodeDiff gets the sha, never the ref: retention may delete
--- the ref while a view of it is still open.
local function baseline_items(root, cb)
  require("util.baseline").list(root, nil, function(entries)
    local items = {}
    for _, e in ipairs(entries or {}) do
      items[#items + 1] = {
        kind = "rev",
        rev = e.sha,
        label = e.subject,
        baseline = e,
        display = " " .. e.subject .. " · " .. when(e.time),
      }
    end
    cb(items)
  end)
end

--- Tab variables for a view of `item` against the working tree. A baseline
--- marks the view as one (vim.t.codediff_baseline, which util.codediff_actions
--- reads for ,X). A round's baseline also names its round (vim.t.ai_review)
--- through ai.review.rounds; without that module the view opens without it.
local function baseline_vars(item)
  local entry = item.baseline
  if not entry then return nil end
  local vars = { codediff_baseline = { sha = entry.sha, kind = entry.kind } }
  if entry.kind == "round" then
    local ok, rounds = pcall(require, "ai.review.rounds")
    if ok and type(rounds) == "table" and type(rounds.review_vars) == "function" then
      local got, review = pcall(rounds.review_vars, entry)
      if got and type(review) == "table" then vars.ai_review = review end
    end
  end
  return vars
end

local function diff_ref()
  local root, reason = repo_root()
  if not root then return warn("Diff against commit/branch", reason) end
  -- Fuzzy pick a baseline or a git ref (branches, tags, recent commits), then
  -- diff the working tree against it. Goes through vim.ui.select, which
  -- snacks.picker (ui_select=true) intercepts.
  local refs, err = ref_items(root)
  if not refs then return warn("Diff against commit/branch", err) end
  baseline_items(root, function(items)
    vim.ui.select(vim.list_extend(items, refs), {
      prompt = "Diff against",
      format_item = function(item) return item.display end,
    }, function(choice)
      if choice then
        require("util.codediff").open({
          root = root,
          args = { choice.rev },
          label = choice.label .. " → working tree",
          tab_vars = baseline_vars(choice),
        })
      end
    end)
  end)
end

---------------------------------------------------------------------------
-- <leader>gk: compare any two ends; <leader>gK: save a baseline
---------------------------------------------------------------------------

local WORKING = { kind = "working", label = "working tree", display = " Working tree" }
local INDEX = { kind = "index", label = "index", display = " Index (staged)" }
local TYPE = { kind = "type", display = " Type a revision… (A...B or A...: from the merge base)" }

-- CodeDiff keeps the live end -- the working tree, else the index -- on the
-- right, so a livelier end picked first trades places.
local LIVE = { rev = 0, index = 1, working = 2 }

local function describe(e)
  return e.kind == "rev" and e.label or "the " .. e.label
end

local function same_end(a, b)
  return a.kind == b.kind and (a.kind ~= "rev" or a.rev == b.rev)
end

--- How CodeDiff shows `left` against `right`: { left, right, args, label,
--- notes, tab_vars? }, or nil and why. The cells, with L/R a baseline or a
--- revision:
---
---   L → working tree   `L`            index → working tree   the status view
---   L → index          `--staged L`   L → R                  `L R`
---
--- A working tree or index picked first trades places with the other end.
---@return table?, string?
local function plan(left, right)
  if same_end(left, right) then
    return nil, ("pick two different ends; both are %s"):format(describe(left))
  end
  local notes = {}
  if LIVE[left.kind] > LIVE[right.kind] then
    left, right = right, left
    notes[#notes + 1] = ("Swapped the ends: CodeDiff shows the %s on the right"):format(right.label)
  end
  local p = { left = left, right = right, notes = notes }
  if left.kind == "index" then
    -- Only the working tree is livelier than the index.
    notes[#notes + 1] = "Index → working tree is the status view: see its Changes group"
    p.args, p.label = {}, "index/HEAD ↔ working tree"
  elseif right.kind == "working" then
    p.args, p.label, p.tab_vars = { left.rev }, left.label .. " → working tree", baseline_vars(left)
  elseif right.kind == "index" then
    p.args, p.label = { "--staged", left.rev }, left.label .. " → index"
  else
    p.args, p.label = { left.rev, right.rev }, left.label .. " → " .. right.label
  end
  return p
end

--- A typed A...B (B against its merge base with A) or A... (the working tree
--- against A's merge base with HEAD), passed to CodeDiff as typed.
local function plan_range(range)
  return {
    left = range,
    args = { range.rev },
    label = range.target and range.rev or range.rev .. " → working tree",
    notes = {},
  }
end

--- The end typed into "Type a revision…", nil when nothing was typed, or nil
--- and why. A range is a whole comparison, so only the first end takes one.
---@return table?, string?
local function typed_end(root, text, first)
  text = vim.trim(text or "")
  if text == "" then return nil end
  local base, target = text:match("^(.+)%.%.%.(.*)$")
  if base then
    if not first then return nil, text .. " is a comparison of its own; type it as the first end" end
    if base:sub(1, 1) == "-" then return nil, "not a revision: " .. base end
    return { kind = "range", rev = text, base = base, target = target ~= "" and target or nil, label = text }
  end
  -- A leading dash would reach CodeDiff's argument parser as a flag.
  if text:sub(1, 1) == "-" or not git(root, "rev-parse", "--verify", "--quiet", text .. "^{commit}") then
    return nil, "not a revision: " .. text
  end
  return { kind = "rev", rev = text, label = text }
end

--- Do both ends of `p` hold the same content? `cb(true|false)`, or
--- `cb(nil, reason)` when git refused a revision. CodeDiff answers an empty
--- comparison with a bare "No changes to show" (#582); this says what was
--- compared instead. The working tree side is a util.baseline snapshot, so
--- untracked files count; a snapshot that fails answers false and the view
--- opens to speak for itself.
local function same_content(root, p, cb)
  local B = require("util.baseline")
  local function run(args, k)
    local ok, err = pcall(vim.system, B.git_cmd(args), { cwd = root, text = true }, function(r)
      vim.schedule(function() k(r) end)
    end)
    if not ok then vim.schedule(function() k({ code = -1, stderr = tostring(err) }) end) end
  end
  local function reason(r, fallback)
    local line = (vim.split(vim.trim(r.stderr or ""), "\n")[1] or ""):gsub("^fatal: ", "")
    return line ~= "" and line or fallback
  end
  local function verdict(r)
    if r.code == 0 then return cb(true) end
    if r.code == 1 then return cb(false) end
    cb(nil, reason(r, "git exited with " .. tostring(r.code)))
  end
  -- `rev` against the working tree, or the index against it when nil.
  local function against_working(rev)
    B.snapshot(root, function(tree)
      if not tree then return cb(false) end
      if rev then
        run({ "diff-tree", "--quiet", "-r", rev, tree }, verdict)
      else
        run({ "diff-index", "--cached", "--quiet", tree, "--" }, verdict)
      end
    end)
  end
  local left, right = p.left, p.right
  if left.kind == "range" then
    run({ "merge-base", left.base, left.target or "HEAD" }, function(r)
      local base = vim.trim(r.stdout or "")
      if r.code ~= 0 or base == "" then return cb(nil, reason(r, "no merge base for " .. left.rev)) end
      if left.target then return run({ "diff-tree", "--quiet", "-r", base, left.target }, verdict) end
      against_working(base)
    end)
  elseif left.kind == "index" then
    against_working(nil)
  elseif right.kind == "working" then
    against_working(left.rev)
  elseif right.kind == "index" then
    run({ "diff-index", "--cached", "--quiet", left.rev, "--" }, verdict)
  else
    run({ "diff-tree", "--quiet", "-r", left.rev, right.rev }, verdict)
  end
end

local function show(root, p)
  same_content(root, p, function(same, why)
    if why then return warn("Compare", why) end
    if same then
      vim.notify("Compare: no differences, " .. p.label, vim.log.levels.INFO)
      return
    end
    for _, note in ipairs(p.notes) do vim.notify(note, vim.log.levels.INFO) end
    require("util.codediff").open({ root = root, args = p.args, label = p.label, tab_vars = p.tab_vars })
  end)
end

local function compare_two()
  local root, reason = repo_root()
  if not root then return warn("Compare", reason) end
  local refs, err = ref_items(root)
  if not refs then return warn("Compare", err) end
  baseline_items(root, function(baselines)
    local items = { WORKING, INDEX }
    vim.list_extend(items, baselines)
    vim.list_extend(items, refs)
    items[#items + 1] = TYPE
    -- One end: a picked item, or a typed revision.
    local function pick(prompt, first, k)
      vim.ui.select(items, { prompt = prompt, format_item = function(item) return item.display end }, function(choice)
        if not choice then return end
        if choice.kind ~= "type" then return k(choice) end
        vim.ui.input({ prompt = first and "From (a revision, A...B or A...)" or "To (a revision)" }, function(text)
          local e, why = typed_end(root, text, first)
          if why then return warn("Compare", why) end
          if e then k(e) end
        end)
      end)
    end
    pick("Compare from", true, function(left)
      if left.kind == "range" then return show(root, plan_range(left)) end
      pick(("Compare %s with"):format(describe(left)), false, function(right)
        local p, why = plan(left, right)
        if not p then return warn("Compare", why) end
        show(root, p)
      end)
    end)
  end)
end

--- Save the working tree as a named baseline for <leader>gk/<leader>gM. It
--- belongs to no session and opens no round; retention.saved prunes the
--- oldest (util.baseline names each one it removes).
local function save_baseline()
  local root, reason = repo_root()
  if not root then return warn("Save baseline", reason) end
  vim.ui.input({ prompt = "Baseline name (empty: the time)" }, function(name)
    if name == nil then return end
    name = vim.trim(name)
    if name == "" then name = os.date("%Y-%m-%d %H:%M:%S") end
    require("util.baseline").save(root, "saved", { subject = "saved · " .. name, Label = name }, function(entry, err)
      if not entry then return warn("Save baseline", tostring(err)) end
      vim.notify(('Saved baseline "%s" (%s); <leader>gk compares against it'):format(name, entry.sha:sub(1, 8)),
        vim.log.levels.INFO)
    end)
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
    { "<leader>gk", compare_two,  desc = "Compare two: worktree / index / baseline / ref", mode = "n" },
    { "<leader>gK", save_baseline, desc = "Save current code as a baseline", mode = "n" },
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
