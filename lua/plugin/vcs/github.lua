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
  keys = {
    {
      "<leader>ghf",
      function() snacks().gitbrowse({ what = "file" }) end,
      desc = "GitHub current file",
      mode = { "n", "x" },
    },
    {
      "<leader>ghF",
      function() snacks().gitbrowse({ what = "permalink" }) end,
      desc = "GitHub file permalink",
      mode = { "n", "x" },
    },
    { "<leader>ghr", function() open_repo_page() end, desc = "GitHub repository" },
    {
      "<leader>ghi",
      needs_gh(function() snacks().picker.gh_issue() end),
      desc = "GitHub issues (open)",
    },
    {
      "<leader>ghI",
      needs_gh(function() snacks().picker.gh_issue({ state = "all" }) end),
      desc = "GitHub issues (all)",
    },
    {
      "<leader>ghp",
      needs_gh(function() snacks().picker.gh_pr() end),
      desc = "GitHub pull requests (open)",
    },
    {
      "<leader>ghP",
      needs_gh(function() snacks().picker.gh_pr({ state = "all" }) end),
      desc = "GitHub pull requests (all)",
    },
    {
      "<leader>ghc",
      needs_gh(function() snacks().picker.gh_actions() end),
      desc = "GitHub current PR",
    },
    { "<leader>gha", function() open_repo_page("actions") end, desc = "GitHub Actions" },
    {
      "<leader>ghn",
      function() vim.ui.open("https://github.com/notifications") end,
      desc = "GitHub notifications",
    },
    { "<leader>ghs", needs_gh(show_status), desc = "GitHub status" },
  },
}
