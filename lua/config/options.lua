local options = {
  -- Indent Options --
  autoindent = true,   -- New lines inherit the indentation of previous lines
  smartindent = true,  -- Make indenting smarter again
  expandtab = true,  -- convert tabs to spaces
  shiftround = true, -- When shifting lines, round the indentation to the nearest multiple of “shiftwidth.”
  shiftwidth = 2,    -- When shifting, indent using two spaces.
  smarttab = true,   -- <Tab> in leading whitespace indents by “shiftwidth”.
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
  scrolloff = 8,      -- Keep context above and below the cursor while scrolling
  sidescrolloff = 5,  -- The number of screen columns to keep to the left and right of the cursor.
  termguicolors = true,
  inccommand = "split",   -- Live preview for substitution commands, in a window listing every match

  -- User Interface Options --
  wildmenu = true,       -- Display command line’s tab complete options as a menu.
  cursorline = true,     -- Highlight the line currently under cursor.
  number = true,         -- Show line numbers on the sidebar.
  relativenumber = true, -- " Show line number on the current line and relative numbers on all other lines.
  mouse = "nv",          -- Enable mouse for scrolling and resizing.
  background = "dark",   -- Use colors that suit a dark background.
  wrap = false,
  showcmd = true,
  -- In the statusline (lualine's %S): noice attaches ext_messages, and the
  -- msg_showcmd it is then sent is one of the events it skips, so a pending
  -- count, operator or register and the Visual selection size showed nowhere.
  showcmdloc = "statusline",
  splitbelow = true,     -- ss / :split put the new window below,
  splitright = true,     -- sv / :vsplit to the right, as their descs say.

  -- Other Options --
  autowrite = true,                        -- Auto write before commands such as :next and :make
  autoread = true,                         -- Automatically re-read files if unmodified inside Vim.
  undofile = true,                         -- Persist undo history across sessions
  undolevels = 10000,                      -- Maximum number of undo levels
  backup = false,                          -- Disable backup
  hidden = true,                           -- Hide files in the background instead of closing them.
  swapfile = false,                        -- Disable swap file
  writebackup = false,                     -- Disable write swap file
  cmdheight = 1,                           -- one command-line row: / and ? search there (noice's bottom_search)
  clipboard = "unnamedplus",               -- allows neovim to access the system clipboard
  completeopt = { "menuone", "noselect" }, -- builtin insert completion (<C-n>, <C-x>…); blink.cmp draws its own menu
  signcolumn = "yes",                      -- always show the sign column, otherwise it would shift the text each time
  showmode = false,                        -- we don't need to see things like -- INSERT -- anymore
  showtabline = 2,                         -- always on, as bufferline keeps it; set here so the first frame has the row too
  laststatus = 3,                          -- Global statusline (single statusline for all windows)
  conceallevel = 2,                        -- Hide markup syntax in markdown, LaTeX etc.; JSON opts out (lua/plugins/lang/json.lua)
}

vim.opt.shortmess:append("c")
vim.opt.smoothscroll = true
vim.opt.spelllang = { "en_us", "cjk" }  -- Skip CJK characters in spell check
-- Filler for the lines one side of a diff lacks (:diffthis, <leader>gd):
-- a diagonal hatch reads as "nothing here", where the default row of dashes
-- looks like content. CodeDiff draws its own filler, with the same glyph.
vim.opt.fillchars:append({ diff = "╱" })

-- Under Ghostty, disable nvim's title updates; ghostty.zsh shell hook manages them
if vim.env.TERM_PROGRAM == "ghostty" then
  options.title = false
end

for k, v in pairs(options) do
  vim.opt[k] = v
end

-- Diagnostics: one global config, set before anything can publish -- LSP,
-- nvim-lint and neotest all report through vim.diagnostic, and a namespace
-- without its own config reads this one. Only the differences from Nvim's
-- defaults are listed, so virtual text and virtual lines stay off.
--
-- statuscol gives diagnostics a single sign cell per line
-- (lua/plugins/ui/statuscol.lua) and keeps the highest-priority sign there.
-- Without severity_sort every diagnostic sign has the same priority, and a
-- line holding an ERROR and a HINT could show the HINT. The glyphs are the
-- ones the statusline counts with; lualine reads them from this config.
local severity = vim.diagnostic.severity
vim.diagnostic.config({
  severity_sort = true,
  signs = {
    text = {
      [severity.ERROR] = "",
      [severity.WARN] = "",
      [severity.INFO] = "",
      [severity.HINT] = "",
    },
  },
})

-- Disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Autoformat on save (toggle with <leader>uF; <leader>uf is the current file)
vim.g.autoformat = true
