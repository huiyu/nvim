-- CodeDiff declares the lazy entry points and view options. User comparison
-- workflows live in git.compare; only util.codediff reads plugin internals.

-- Read at spec evaluation, matching the setting applied to CodeDiff history.
local function history_desc(what)
  local limit = require("util.settings").git().history_limit
  return ("%s (%s, no merges)"):format(what, limit and ("recent " .. limit) or "all")
end

return {
  "esmuellert/codediff.nvim",
  -- v4.0.6. util.codediff reads internals this version has and checks it at
  -- setup; moving the pin means re-running tests/codediff_spec.lua first.
  commit = "09d9ebef2cc5a5c04db7a349cd6c61bdf84ecc8e",
  cmd = "CodeDiff",
  keys = {
    { "<leader>gv", function() require("git_review.compare").status() end, desc = "Diff view", mode = "n" },
    { "<leader>gq", function() require("git_review.compare").close() end, desc = "Close diff view", mode = "n" },
    { "<leader>gm", function() require("git_review.compare").main() end, desc = "Diff against main branch", mode = "n" },
    { "<leader>gM", function() require("git_review.compare").baseline_or_ref() end, desc = "Diff against baseline/ref…", mode = "n" },
    {
      "<leader>gk", function() require("git_review.compare").two() end,
      desc = "Compare two (working tree/index/baseline/ref)…", mode = "n",
    },
    { "<leader>gK", function() require("git_review.compare").save_baseline() end, desc = "Save baseline…", mode = "n" },
    { "<leader>gh", function() require("git_review.compare").file_history() end, desc = history_desc("File history"), mode = "n" },
    { "<leader>gH", function() require("git_review.compare").repo_history() end, desc = history_desc("Repo history"), mode = "n" },
  },
  opts = {
    -- The explorer lists every untracked file, as `<leader>gv`'s clean-tree
    -- check counts them. Line stats stay off, as by default: with them on, a
    -- revision view would list its files through a second code path. Files
    -- show as a directory tree (`i` toggles a flat list): a branch or a round
    -- easily touches a hundred files across a dozen directories.
    explorer = { untracked = "all", line_stats = { enabled = false }, view_mode = "tree" },
    history = { view_mode = "tree" },
    keymaps = {
      view = {
        -- q only closes from the explorer and history panels
        -- (util.codediff); in a diff pane it stays macro recording.
        quit = false,
        -- View actions join the comma menu: ,P focuses and ,B toggles the
        -- panel; ,I and ,z because `t` is flash and `gc` is the comment
        -- operator.
        toggle_explorer = "<localleader>B",
        focus_explorer = "<localleader>P",
        toggle_layout = "<localleader>I",
        toggle_compact = "<localleader>z",
        -- Index edits are ours (,S ,U ,X): upstream's stage the hunk against
        -- the revision rather than the index in a rev-vs-working-tree view.
        stage_hunk = false,
        unstage_hunk = false,
        discard_hunk = false,
        -- `-` is oil's parent directory outside a view; util.codediff gives it
        -- to the status view's explorer as stage/unstage and blocks it in
        -- every other buffer of a view, where oil would swap a pane.
        toggle_stage = false,
        toggle_staged_view = false, -- gS is splitjoin
        align_move = false,         -- gm is a builtin
        -- Kept: ]c [c ]f [f do dp gf g? ih. util.codediff adds ]h [h, the
        -- same hunk moves under this config's hunk key.
      },
      -- Re-installed by util.codediff on the status view's explorer only:
      -- in a revision view the explorer's X deletes files that are merely
      -- untracked in the index.
      explorer = { stage_all = false, unstage_all = false, restore = false },
      -- Conflict choices, on ,g so ,c (codelens) stays immediate:
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
    require("git_review.view").setup(opts, {
      history_limit = function() return require("util.settings").git().history_limit end,
      max_file_size = function() return require("util.settings").git().max_file_size end,
    })
    -- util.codediff_actions installs the hunk keys (,S ,U ,X) on every pass.
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("codediff_actions", { clear = true }),
      pattern = "CodeDiffKeys",
      callback = function(ev) require("git_review.actions").attach(ev.data.tabpage) end,
    })
  end,
}
