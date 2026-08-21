---@module "autocmds"
---Auto commands and user commands for Neovim configuration
---
---Defines custom commands and automatic behaviors for improved workflow.
---Includes window management commands and performance optimizations.

-- API shortcuts for creating commands and autocommands
local cmd = vim.api.nvim_create_user_command
local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

--- Window Management Commands
--- Custom commands for efficient window handling

-- Close all windows except current one (useful for cleaning up splits)
cmd("WindowCloseOthers", function()
  require("util.window").close_others()
end, { desc = "Close other windows" })

-- Close current window safely
cmd("WindowCloseCurrent", function()
  require("util.window").close_current()
end, { desc = "Close current window" })

-- Reach the editor area in one press from a sidebar or terminal, and return
-- to the window it came from on a second press
cmd("WindowFocusEditor", function()
  require("util.window").focus_editor()
end, { desc = "Focus editor window (toggle back)" })

-- Track the editor window the cursor last occupied so WindowFocusEditor lands
-- on the file being worked on instead of a fixed slot in the layout.
-- WinLeave, not WinEnter: a window opened by `split` still shows a file buffer
-- when WinEnter fires and only becomes a terminal or sidebar afterwards, which
-- would record a window that is not an editor window at all.
autocmd("WinLeave", {
  group = augroup("track_editor_win", { clear = true }),
  callback = function()
    require("util.window").track_editor_win()
  end,
})

-- Optimize terminal buffer settings for TUI apps (for example coding agents)
-- Disables line numbers and scrolloff to prevent rendering glitches
autocmd("TermOpen", {
  group = augroup("terminal_ui_fix", { clear = true }),
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.scrolloff = 0
    vim.opt_local.sidescrolloff = 0
    vim.opt_local.signcolumn = "no"
  end,
})

-- Set cwd when opening a directory
autocmd("VimEnter", {
  group = augroup("vimenter_cd", { clear = true }),
  callback = function(data)
    if vim.fn.isdirectory(data.file) == 1 then
      vim.cmd.cd(data.file)
    end
  end
})

-- Highlight on yank (brief flash after copying)
autocmd("TextYankPost", {
  group = augroup("highlight_yank", { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Restore cursor position when reopening a file
autocmd("BufReadPost", {
  group = augroup("restore_cursor", { clear = true }),
  callback = function(event)
    local exclude = { "gitcommit" }
    local buf = event.buf
    if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].lazyvim_last_loc then
      return
    end
    vim.b[buf].lazyvim_last_loc = true
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local lcount = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Close some filetypes with <q>
autocmd("FileType", {
  group = augroup("close_with_q", { clear = true }),
  pattern = {
    "help", "lspinfo", "notify", "qf", "query",
    "startuptime", "checkhealth", "neotest-output",
    "neotest-summary", "neotest-output-panel", "dbout",
    "gitsigns-blame",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", {
      buffer = event.buf,
      silent = true,
    })
  end,
})

-- Auto reload files when changed externally.
-- `autoread` alone never polls the disk -- nvim only stats the file when one of
-- these events fires. FocusGained/TermClose/TermLeave (the LazyVim default) all
-- assume you leave and come back. They never fire when an agent edits the file
-- while you sit in the same nvim reading it -- e.g. a coding agent running in a
-- terminal buffer in a neighbouring split: nvim never loses OS focus, the
-- terminal is never closed, and terminal mode is never left.
-- BufEnter covers switching back to the buffer; CursorHold covers staying in it
-- (fires `updatetime` ms after the cursor stops -- 300ms here).
autocmd({
  "FocusGained", "TermClose", "TermLeave",
  "BufEnter", "CursorHold", "CursorHoldI",
}, {
  group = augroup("checktime", { clear = true }),
  callback = function()
    -- Running checktime while the command line is open interrupts input.
    if vim.fn.mode() == "c" then return end

    -- The command-line window (`q:`) needs its own test: `:help cmdline.txt`
    -- says "Vim will be in Normal mode when the editor is opened", so mode()
    -- reports "n" there and the check above lets it through. `checktime` is
    -- forbidden in that window, and with updatetime at 300ms an unguarded
    -- CursorHold raises E11 several times a second.
    if vim.fn.getcmdwintype() ~= "" then return end

    vim.cmd("checktime")
  end,
})

-- Reloading is otherwise silent, which is worse than not reloading: you keep
-- reading what you believe is the old content. Say so.
autocmd("FileChangedShellPost", {
  group = augroup("checktime", { clear = false }),
  callback = function()
    vim.notify("File changed on disk -- buffer reloaded", vim.log.levels.WARN)
  end,
})

-- Resize splits when window is resized (respects winfixwidth/winfixheight)
autocmd("VimResized", {
  group = augroup("resize_splits", { clear = true }),
  callback = function()
    -- Equalize every tab WITHOUT physically switching into it. nvim_win_call is
    -- a lightweight context switch that runs `wincmd =` against the target tab
    -- without firing the Tab/Win Enter/Leave autocmd cascade that `:tabnext`
    -- would on every resize.
    local win_util = require("util.window")
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      local wins = vim.api.nvim_tabpage_list_wins(tab)
      if wins[1] then
        vim.api.nvim_win_call(wins[1], function()
          win_util.equalize_respecting_fixed()
        end)
      end
    end
  end,
})

-- Wrap and spell check in text filetypes
autocmd("FileType", {
  group = augroup("wrap_spell", { clear = true }),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

-- Auto create parent directories when saving a file
autocmd("BufWritePre", {
  group = augroup("auto_create_dir", { clear = true }),
  callback = function(event)
    if event.match:match("^%w%w+:[\\/][\\/]") then
      return
    end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})
