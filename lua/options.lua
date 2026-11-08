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
  cmdheight = 1,                           -- more space in the neovim command line for displaying messages
  clipboard = "unnamedplus",               -- allows neovim to access the system clipboard
  completeopt = { "menuone", "noselect" }, -- mostly just for cmp
  signcolumn = "yes",                      -- always show the sign column, otherwise it would shift the text each time
  showmode = false,                        -- we don't need to see things like -- INSERT -- anymore
  showtabline = 2,                         -- always on, as bufferline keeps it; set here so the first frame has the row too
  laststatus = 3,                          -- Global statusline (single statusline for all windows)
  conceallevel = 2,                        -- Hide markup syntax in markdown, LaTeX etc.; JSON opts out (lua/lang/json.lua)
}

vim.opt.shortmess:append("c")
vim.opt.smoothscroll = true
vim.opt.spelllang = { "en_us", "cjk" }  -- Skip CJK characters in spell check
-- Filler for the lines one side of a diff lacks (diffview, :diffthis): a
-- diagonal hatch reads as "nothing here", where the default row of dashes
-- looks like content.
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
-- (lua/plugin/ui/statuscol.lua) and keeps the highest-priority sign there.
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

-- Messages and the command line: Nvim's own ui2 instead of the legacy message
-- grid. No "Press ENTER" prompt; output taller than 'cmdheight' collapses to a
-- `[+N]` marker, and `g<` / `:messages` open it in a pager window (q closes).
-- Default routing keeps messages in the cmdline row, as before ui2.
--
-- Experimental, and reached through an internal module path, hence the pcall:
-- if a later Nvim moves it, startup falls back to the legacy UI instead of
-- failing. enable() returns early when no UI is attached, so --headless runs
-- (the specs, the startup check) keep plain stdout/stderr messages.
--
-- A UI that attaches later (`nvim --headless --listen` + `nvim --remote-ui`)
-- gets it on its first UIEnter instead; a headless run never fires that event.
-- The snacks notifier makes the same deferral (lua/plugin/editor/snacks.lua).
--
-- ui2 keeps its four floats (cmd, msg, pager, dialog) in whichever tabpage is
-- current, so nvim_tabpage_list_wins() never returns just the layout: a "last
-- window?" check must count non-floating windows only.
local has_ui2, ui2 = pcall(require, "vim._core.ui2")
if has_ui2 then
  if #vim.api.nvim_list_uis() > 0 then
    ui2.enable({})
  else
    vim.api.nvim_create_autocmd("UIEnter", {
      once = true,
      callback = function() ui2.enable({}) end,
      desc = "Enable ui2 for a UI that attached after startup",
    })
  end
end

-- Disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Autoformat on save (toggle with <leader>uf)
vim.g.autoformat = true
