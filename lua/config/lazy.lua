local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
-- lazy.nvim: install it on first start, then load every spec under
-- lua/plugins/. Required last by lua/config/init.lua, so the specs see the
-- options, keymaps and AI facade set up before them.

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    require("editor_core.logger").error("Failed to install lazy.nvim: %s", out)
    error("Failed to install lazy.nvim")
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  lockfile = root .. "/lazy-lock.json",
  -- Import order is merge order: a lang spec extends the coding/ui specs of
  -- the same plugin (nvim-lspconfig, conform, nvim-dap, treesitter...), so
  -- plugins.lang stays last.
  spec = {
    { import = "plugin.editor" }, -- editing, navigation, pickers, panels
    { import = "plugin.coding" }, -- LSP, completion, formatting, linting, DAP, tests
    { import = "plugin.ai" },     -- Claude Code, CodeCompanion, ghost text
    { import = "plugin.ui" },     -- colorscheme, statusline, tabline, treesitter
    { import = "plugin.git" },    -- CodeDiff, gitsigns, GitHub
    { import = "plugin.lang" },   -- per-language servers, tools, adapters
  },
  -- A spec with no event/cmd/keys/ft trigger stays unloaded until something
  -- requires it, so anything that must run at startup says `lazy = false`.
  defaults = { lazy = true, version = false },
  -- Off until broken rockspecs are fixed (e.g. nvim-dap-python).
  rocks = { enabled = false },
  install = { missing = true, colorscheme = { "solarized-osaka" } },
  -- Check for updates once a day, silently; review and apply with :Lazy.
  checker = { enabled = true, notify = false, frequency = 86400 },
  performance = {
    cache = { enabled = true },
    rtp = {
      reset = false,
      paths = { root },
      -- netrw is disabled earlier, through vim.g.loaded_netrw* in
      -- local-plugin/editor-core.nvim/lua/editor_core/options.lua.
      disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" },
    },
  },
  ui = { border = "rounded" },
})
