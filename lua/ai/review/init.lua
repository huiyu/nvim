-- The review view behind <leader>av. A placeholder until the view itself
-- lands: rounds are already recorded (lua/ai/review/rounds.lua), there is just
-- nothing to show them in yet.
local M = {}

function M.open()
  vim.notify("The review view is not available yet; rounds are still recorded (<leader>aV opens one now).",
    vim.log.levels.WARN, { title = "AI review" })
end

return M
