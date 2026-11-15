-- Host-specific aggregation; individual packages own their diagnostics.
local M = {}
function M.check()
  require("editor_core.health").check()
  require("agent_workbench.health").check()
  require("git_review.health").check({ retention = require("agent_workbench.review.settings").get().retention })
  require("llama_service.health").check()
end
return M
