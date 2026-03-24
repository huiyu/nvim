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

-- Optimize terminal buffer settings for TUI apps (e.g. Claude Code)
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

-- Auto reload files when changed externally
autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
  group = augroup("checktime", { clear = true }),
  callback = function()
    if vim.o.buftype ~= "nofile" then
      vim.cmd("checktime")
    end
  end,
})

-- Resize splits when window is resized (respects winfixwidth/winfixheight)
autocmd("VimResized", {
  group = augroup("resize_splits", { clear = true }),
  callback = function()
    local current_tab = vim.fn.tabpagenr()
    local total_tabs = vim.fn.tabpagenr("$")
    for tab = 1, total_tabs do
      vim.cmd("tabnext " .. tab)
      require("util.window").equalize_respecting_fixed()
    end
    vim.cmd("tabnext " .. current_tab)
  end,
})

-- Restore fixed-width panels when split count changes (open/close splits)
-- Only restores fixed panels (no equalization) to avoid disrupting manual resizes
do
  local function count_splits()
    local count = 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == "" then
        count = count + 1
      end
    end
    return count
  end
  local prev_split_count = count_splits()
  autocmd({ "WinNew", "WinClosed" }, {
    group = augroup("restore_fixed_panels", { clear = true }),
    callback = function()
      vim.schedule(function()
        local cur_count = count_splits()
        if cur_count ~= prev_split_count then
          prev_split_count = cur_count
          require("util.window").restore_fixed_panels()
        end
      end)
    end,
  })
end

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
