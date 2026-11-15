local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
return {
  dir = root .. "/local-plugin/git-review.nvim", name = "git-review.nvim", main = "git_review",
  opts = function()
    local opts = require("util.settings").git()
    opts.resolve = require("util.settings").git
    opts.labels = function(method, value, callback)
      return require("agent_workbench.review.labels")[method](value, callback)
    end
    opts.review_vars = function(entry) return require("agent_workbench.review.rounds").review_vars(entry) end
    opts.close_aux = function(tab) return require("editor_core.diffsplit").close(tab) end
    return opts
  end,
}
