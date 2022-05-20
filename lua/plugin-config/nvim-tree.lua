local status_ok, nvim_tree = pcall(require, "nvim-tree")

if not status_ok then
  vim.notify("nvim-tree not found!")
end

local keymaps = {
  -- open file
  { key = { "<CR>", "o", "<2-LeftMouse>" }, action = "edit" },
  -- open file on a split window
  { key = "<C-v>", action = "vsplit" },
  { key = "<C-s>", action = "split" },
  -- show/hide file
  { key = "i", action = "toggle_ignored" }, -- Ignore (node_modules)
  { key = ".", action = "toggle_dotfiles" }, -- Hide (dotfiles)
  -- other file ac action
  { key = "<BS>", action = "close_node" },
  { key = "<Tab>", action = "preview" },
  { key = "R", action = "refresh" },
  { key = "a", action = "create" },
  { key = "d", action = "remove" },
  { key = "r", action = "rename" },
  { key = "<C-r>", action = "full_rename" },
  { key = "x", action = "cut" },
  { key = "c", action = "copy" },
  { key = "y", action = "copy_name" },
  { key = "gy", action = "copy_absolute_path" },
  { key = "p", action = "paste" },
  { key = "S", action = "system_open" },
  { key = "W", action = "collapse_all" },
  { key = "<C-k>", action = "toggle_file_info" },
  { key = ".", action = "run_file_command" },
}

vim.g.nvim_tree_group_empty = 1

nvim_tree.setup({
  hijack_netrw = false,
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
    side = "left",
    hide_root_folder = false,

    -- custom keymaps
    mappings = {
      custom_only = true,
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

vim.cmd("silent! autocmd! FileExplorer *")
vim.cmd("autocmd VimEnter * ++once silent! autocmd! FileExplorer *")
vim.cmd([[
  autocmd BufEnter * ++nested if winnr('$') == 1 && bufname() == 'NvimTree_' . tabpagenr() | quit | endif
]])
