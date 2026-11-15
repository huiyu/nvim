local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
return {
  dir = root .. "/local-plugin/agent-workbench.nvim", name = "agent-workbench.nvim", main = "agent_workbench",
  lazy = false, priority = 9000,
  opts = function()
    local opts = vim.deepcopy(require("config.ai"))
    local git = require("util.settings").git()
    opts.review = vim.tbl_deep_extend("force", vim.deepcopy(require("config.review")), {
      max_file_size = git.max_file_size, history_limit = git.history_limit, retention = { saved = git.retention.saved },
    })
    opts.keymaps = require("config.keymaps").ai
    opts.integrations = { companion = true, review = true }
    opts.callbacks = {
      project_root = require("util.cwd").project_root,
      editor_win = function() return require("editor_core.window").editor_win() end,
      origin_tab = function(tab) return require("editor_core.window").origin_tab(tab) end,
      notify_error = function(err) return require("editor_core.vim_error").notify(err) end,
    }
    return opts
  end,
  config = function(_, opts)
    require("agent_workbench").setup(opts)
    require("editor_core.terminal").set_agent_test(require("agent_workbench.terminal").is_agent_buf)
  end,
}
