# git-review.nvim

Immutable worktree snapshots, saved comparisons/history and CodeDiff views for
Neovim. `require("git_review")` is inert. The host calls `setup(opts)` through a
local lazy.nvim spec and owns the concrete `<leader>g` mappings.

Options are `history_limit = 100` (or `false`), `max_file_size = 10485760`,
`retention = { saved = 10 }`, plus an optional `resolve()` callback for live host
policy. `options()` returns a copy of the effective values. Comparison labels,
review trailers and auxiliary-view closing are injected callbacks, rather than
imports from an AI module. CodeDiff is required only when opening its view.

`git_review.baseline` owns snapshots under `refs/nvim-review/`, using a unique
temporary index and preserving HEAD, the real index, branches, stash and their
reflogs. `git_review.view` is the one CodeDiff internals boundary;
`git_review.actions` and `compare` call that owner. Health has the narrow library
version check. Round interpretation and delivery belong to agent-workbench.nvim.

The baseline, compare and view APIs and safety rules are documented in the
host's `docs/UTILITIES.md` and `AGENTS.md`. Existing refs/drafts retain their
storage format and worktree identity across this directory migration.
