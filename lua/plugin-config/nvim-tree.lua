local status_ok, nvim_tree = pcall(require, "nvim-tree")

if not status_ok then
  vim.notify("nvim-tree not found!")
end

local keymaps = {
  -- open file
  { key = { "<CR>", "o", "<2-LeftMouse>" }, action = "edit" },
  -- open file on a split window
  { key = "v", action = "vsplit" },
  { key = "s", action = "split" },
  -- show/hide file
  { key = "i", action = "toggle_ignored" }, -- Ignore (node_modules)
  { key = ".", action = "toggle_dotfiles" }, -- Hide (dotfiles)
  -- other file ac action
  { key = "<F5>", action = "refresh" },
  { key = "a", action = "create" },
  { key = "d", action = "remove" },
  { key = "r", action = "rename" },
  { key = "x", action = "cut" },
  { key = "c", action = "copy" },
  { key = "p", action = "paste" },
  { key = "S", action = "system_open" },
}

vim.g.nvim_tree_group_empty = 1

nvim_tree.setup({
  git = { enable = false },
  update_cwd = true,
  update_focused_file = {
    enable = true,
    update_cwd = true,
  },

  filters = {
    dotfiles = false,
    custom = { "node_modules" },
  },

  view = {
    width = 40,
    side = "right",
    hide_root_folder = false,

    -- custom keymaps
    mappings = {
      custom_only = false,
      list = keymaps,
    },

    number = false,
    relativenumber = false,

    signcolumn = "yes",
  },

  actions = {
    open_file = {
      resize_window = true,
      quit_on_open = false,
    },
  },

  system_open = {
    cmd = "open",
  },
})

vim.cmd([[
  autocmd BufEnter * ++nested if winnr('$') == 1 && bufname() == 'NvimTree_' . tabpagenr() | quit | endif
]])
