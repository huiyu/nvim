-- Editable defaults for the agent review loop. Runtime validation and merging
-- live in agent_workbench.review.settings. Override only what you need from init.lua:
--
--   vim.g.ai_review = { retention = { rounds = 30 } }
--
-- The override is read on every use, so a change at runtime applies next time.
-- Change it by assigning a whole table:
-- vim.g hands out copies, so `vim.g.ai_review.retention.rounds = 30` is lost.

return {
  retention = {
    -- Newest round baselines kept per worktree (git_review.baseline prune). A round
    -- with a non-empty feedback draft is never pruned.
    rounds = 20,
  },
  -- false: that source never opens a round. For the native agents no hook is
  -- injected; for CodeCompanion no on_before_submit callback is added.
  sources = {
    codex = true,
    codecompanion_acp = true,
    codecompanion_http = true,
  },
  -- How long local-plugin/agent-workbench.nvim/scripts/agent-hook and CodeCompanion's on_before_submit wait for
  -- the baseline before letting the prompt through. 0 never waits.
  hook_wait_ms = 2500,
  -- A native session that cannot be confirmed before delivery: ask, or refuse.
  unknown_session = "confirm", -- "confirm" or "refuse"
  -- Agents whose delivery is confirmed every time, even when the session is
  -- known, e.g. { "codex" }.
  always_confirm = {}, -- { "codex" }
  -- false: when a round's owner is gone, refuse without offering "send to the
  -- current session".
  redirect = true,
  -- How long a native agent has to open its prompt editor for a delivered
  -- feedback draft before the delivery counts as failed and the draft is kept.
  seed_ttl_ms = 10000,

}
