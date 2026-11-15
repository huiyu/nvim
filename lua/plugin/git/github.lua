local function snacks()
  return _G.Snacks or require("snacks")
end

local function needs_gh(callback)
  return function()
    if vim.fn.executable("gh") ~= 1 then
      vim.notify(
        "GitHub CLI (gh) is not installed",
        vim.log.levels.WARN,
        { title = "GitHub" }
      )
      return
    end
    callback()
  end
end

local function open_repo_page(path)
  snacks().gitbrowse({
    what = "repo",
    open = function(url)
      url = url:gsub("/+$", "")
      vim.ui.open(path and (url .. "/" .. path) or url)
    end,
  })
end

local function show_status()
  local cwd = snacks().git.get_root() or vim.uv.cwd() or vim.fn.getcwd()
  vim.system({ "gh", "status" }, { cwd = cwd, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = vim.trim(result.stderr or "")
        vim.notify(
          message ~= "" and message or "gh status failed",
          vim.log.levels.ERROR,
          { title = "GitHub" }
        )
        return
      end

      local output = vim.trim(result.stdout or "")
      snacks().win({
        title = " GitHub Status ",
        text = output ~= "" and output or "No GitHub activity found.",
        ft = "text",
        enter = true,
        border = "rounded",
        width = 0.9,
        height = 0.8,
        wo = { wrap = false },
      })
    end)
  end)
end

return {
  "folke/snacks.nvim",
  opts = {
    gh = {
      -- Issue/PR buffers are reading views; keep the inherited fold depths
      -- out of the gutter, alongside Snacks' disabled line numbers.
      wo = { foldcolumn = "0" },
    },
  },
  keys = {
    {
      "<leader>Gf",
      function() snacks().gitbrowse({ what = "file" }) end,
      desc = "File (browser)",
      mode = { "n", "x" },
    },
    {
      "<leader>GF",
      function() snacks().gitbrowse({ what = "permalink" }) end,
      desc = "File permalink (browser)",
      mode = { "n", "x" },
    },
    { "<leader>Gr", function() open_repo_page() end, desc = "Repo (browser)" },
    {
      "<leader>Gi",
      needs_gh(function() snacks().picker.gh_issue() end),
      desc = "Issues (open)",
    },
    {
      "<leader>GI",
      needs_gh(function() snacks().picker.gh_issue({ state = "all" }) end),
      desc = "Issues (all)",
    },
    {
      "<leader>Gp",
      needs_gh(function() snacks().picker.gh_pr() end),
      desc = "PRs (open)",
    },
    {
      "<leader>GP",
      needs_gh(function() snacks().picker.gh_pr({ state = "all" }) end),
      desc = "PRs (all)",
    },
    {
      "<leader>Gc",
      needs_gh(function() snacks().picker.gh_actions() end),
      desc = "Current PR actions…",
    },
    { "<leader>Ga", function() open_repo_page("actions") end, desc = "Workflow runs (browser)" },
    {
      "<leader>Gn",
      function() vim.ui.open("https://github.com/notifications") end,
      desc = "Notifications (browser)",
    },
    { "<leader>Gs", needs_gh(show_status), desc = "Status (gh status)" },
  },
}
