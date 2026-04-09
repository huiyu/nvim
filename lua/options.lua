local options = {
  -- Indent Options --
  autoindent = true,   -- New lines inherit the indentation of previous lines
  smartindent = true,  -- Make indenting smarter again
  expandtab = true,  -- convert tabs to spaces
  shiftround = true, -- When shifting lines, round the indentation to the nearest multiple of “shiftwidth.”
  shiftwidth = 2,    -- When shifting, indent using two spaces.
  smarttab = true,   -- Insert “tabstop” number of spaces when the “tab” key is pressed.
  tabstop = 2,       -- Indent using two spaces.

  -- Search Options --
  hlsearch = true,   -- Enable search highlighting.
  ignorecase = true, -- Ignore case when searching
  incsearch = true,  -- Incremental search that shows partial matches
  smartcase = true,  -- Automatic switch to case sensitive when search query contains an uppercase letter
  grepprg = "rg --vimgrep", -- Use ripgrep for :grep
  grepformat = "%f:%l:%c:%m", -- Parse ripgrep output

  -- Performance Options --
  updatetime = 300, -- faster completion (4000ms default)

  -- Text Rendering Options --
  encoding = "utf-8", -- " Use unicode file encoding
  fileencoding = "utf-8",
  scrolloff = 4,      -- The number of screen lines to keep above below the cursor
  sidescrolloff = 5,  -- The number of screen columns to keep to the left and right of the cursor.
  termguicolors = true,
  inccommand = "nosplit", -- Live preview for substitution commands

  -- User Interface Options --
  wildmenu = true,       -- Display command line’s tab complete options as a menu.
  cursorline = true,     -- Highlight the line currently under cursor.
  number = true,         -- Show line numbers on the sidebar.
  relativenumber = true, -- " Show line number on the current line and relative numbers on all other lines.
  mouse = "nv",          -- Enable mouse for scrolling and resizing.
  background = "dark",   -- Use colors that suit a dark background.
  wrap = false,
  showcmd = true,

  -- Other Options --
  autowrite = true,                        -- Auto save when switching buffers or leaving vim
  autoread = true,                         -- Automatically re-read files if unmodified inside Vim.
  undofile = true,                         -- Persist undo history across sessions
  undolevels = 10000,                      -- Maximum number of undo levels
  backup = false,                          -- Disable backup
  hidden = true,                           -- Hide files in the background instead of closing them.
  swapfile = false,                        -- Disable swap file
  writebackup = false,                     -- Disable write swap file
  cmdheight = 1,                           -- more space in the neovim command line for displaying messages
  clipboard = "unnamedplus",               -- allows neovim to access the system clipboard
  completeopt = { "menuone", "noselect" }, -- mostly just for cmp
  signcolumn = "yes",                      -- always show the sign column, otherwise it would shift the text each time
  showmode = false,                        -- we don't need to see things like -- INSERT -- anymore
  showtabline = 1,                         -- always show tabs
  laststatus = 3,                          -- Global statusline (single statusline for all windows)
  conceallevel = 2,                        -- Hide markup syntax in markdown etc.
}

vim.opt.shortmess:append("c")
vim.opt.smoothscroll = true
vim.opt.spelllang = { "en_us", "cjk" }  -- Skip CJK characters in spell check

-- Under Ghostty, disable nvim's title updates; ghostty.zsh shell hook manages them
if vim.env.TERM_PROGRAM == "ghostty" then
  options.title = false
end

for k, v in pairs(options) do
  vim.opt[k] = v
end

-- Disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Autoformat on save (toggle with <leader>uf)
vim.g.autoformat = true
