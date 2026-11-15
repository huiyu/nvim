-- Editable preferences. Requiring this file only returns values.
return {
  autoindent = true,   -- New lines inherit the indentation of previous lines
  smartindent = true,  -- Make indenting smarter again
  expandtab = true,  -- convert tabs to spaces
  shiftround = true, -- When shifting lines, round the indentation to the nearest multiple of “shiftwidth.”
  shiftwidth = 2,    -- When shifting, indent using two spaces.
  smarttab = true,   -- <Tab> in leading whitespace indents by “shiftwidth”.
  tabstop = 2,       -- Indent using two spaces.
  hlsearch = true,   -- Enable search highlighting.
  ignorecase = true, -- Ignore case when searching
  incsearch = true,  -- Incremental search that shows partial matches
  smartcase = true,  -- Automatic switch to case sensitive when search query contains an uppercase letter
  updatetime = 300, -- faster completion (4000ms default)
  fileencoding = "utf-8",
  scrolloff = 8,      -- Keep context above and below the cursor while scrolling
  sidescrolloff = 5,  -- The number of screen columns to keep to the left and right of the cursor.
  inccommand = "split",   -- Live preview for substitution commands, in a window listing every match
  cursorline = true,     -- Highlight the line currently under cursor.
  number = true,         -- Show line numbers on the sidebar.
  relativenumber = true, -- " Show line number on the current line and relative numbers on all other lines.
  mouse = "nv",          -- Enable mouse for scrolling and resizing.
  wrap = false,
  splitbelow = true,     -- ss / :split put the new window below,
  splitright = true,     -- sv / :vsplit to the right, as their descs say.
  autowrite = true,                        -- Auto write before commands such as :next and :make
  autoread = true,                         -- Automatically re-read files if unmodified inside Vim.
  undofile = true,                         -- Persist undo history across sessions
  undolevels = 10000,                      -- Maximum number of undo levels
  backup = false,                          -- Disable backup
  hidden = true,                           -- Hide files in the background instead of closing them.
  swapfile = false,                        -- Disable swap file
  writebackup = false,                     -- Disable write swap file
  clipboard = "unnamedplus",               -- allows neovim to access the system clipboard
  conceallevel = 2,                        -- Hide markup syntax in markdown, LaTeX etc.; JSON opts out (lua/plugin/lang/json.lua)
  smoothscroll = true,
  spelllang = { "en_us", "cjk" },
}
