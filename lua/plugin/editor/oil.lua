-- Directory-as-buffer file management.
--
-- netrw is disabled in lua/options.lua, so until now a directory buffer landed
-- on an empty nameless buffer -- `:e lua/` did nothing useful. oil fills that,
-- and adds the operation the file tree is worst at: editing the listing as
-- text. Rename a line and `:w`; `dd` a line and `p` it in another directory to
-- move the file; write a new line to create one. Changes are staged until `:w`,
-- which shows the resulting shell-level operations for confirmation.
--
-- Complementary to the tree on ;e, not a replacement: the tree stays for
-- browsing, oil is opened for a specific edit and closed again.
local function open_oil(floating)
  local dir
  if vim.bo.buftype == "terminal" then
    -- Snacks protects its terminal window with fixbuf. Opening Oil there
    -- makes it swap buffers during :edit, leaving focus on the agent. Choose
    -- and focus an editor window first, keeping the terminal's directory.
    dir = require("util.cwd").buffer_dir()
    vim.api.nvim_set_current_win(require("util.window").ensure_editor_win())
    vim.cmd("stopinsert")
  end
  if floating then
    require("oil").open_float(dir, { preview = {} })
  else
    if dir and vim.api.nvim_buf_get_name(0) == "" then
      -- :edit can reuse an unnamed buffer. Pre-create Oil's buffer so its
      -- original-buffer record still points at the blank editor when q runs.
      vim.fn.bufadd("oil://" .. dir:gsub("/+$", "") .. "/")
    end
    require("oil").open(dir)
  end
end

return {
  "stevearc/oil.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  cmd = "Oil",
  -- `default_file_explorer` only takes effect once oil is loaded, and lazy.nvim
  -- has no "this buffer is a directory" trigger. Registering the check here
  -- costs nothing at startup -- it does not require the plugin -- and pulls oil
  -- in only when a directory is actually opened, so both `nvim lua/` and
  -- `:e lua/` land in oil while an ordinary session never loads it.
  init = function()
    local function open_directory_buffer(buf, path)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        -- BufNew also fires for background buffers created by :badd, session
        -- restoration and plugins. Only replace a window that still displays
        -- this exact directory buffer; a background add must stay background.
        local wins = vim.fn.win_findbuf(buf)
        if #wins == 0 then return end
        vim.api.nvim_win_call(wins[1], function()
          if vim.api.nvim_get_current_buf() == buf then
            require("oil").open(path)
          end
        end)
      end)
    end

    vim.api.nvim_create_autocmd("BufNew", {
      group = vim.api.nvim_create_augroup("oil_directory_buffers", { clear = true }),
      callback = function(ev)
        if ev.file ~= "" and vim.fn.isdirectory(ev.file) == 1 then
          open_directory_buffer(ev.buf, ev.file)
        end
      end,
      desc = "Open a directory buffer in oil",
    })

    -- A directory named on the command line has its buffer created before the
    -- autocmd above exists, so `nvim lua/` needs its own check.
    local first = vim.fn.argc() > 0 and vim.fn.argv(0) or nil
    if type(first) == "string" and vim.fn.isdirectory(first) == 1 then
      open_directory_buffer(vim.api.nvim_get_current_buf(), first)
    end
  end,
  keys = {
    { ";o", function() open_oil(true) end,
      desc = "Oil file manager (float)" },
    -- oil's own convention, and the reason it is worth the shadowing: `-`
    -- reaches the current file's directory in one key. It replaces the builtin
    -- "first non-blank of the previous line" motion, which `k^` already covers.
    { "-", function() open_oil(false) end, desc = "Oil: parent directory" },
  },
  opts = {
    default_file_explorer = true,
    columns = {
      "icon",
      { "permissions", highlight = "Type" },
      { "size", highlight = "String" },
      { "mtime", highlight = "Keyword" },
    },
    -- oil's defaults claim three keys this config already owns globally:
    -- <C-h>/<C-l> are window navigation everywhere (lua/mappings.lua) and must
    -- keep working inside an oil buffer, and `gx` opens the URL under the
    -- cursor. Turn those off and put oil's actions on keys that are free here.
    use_default_keymaps = true,
    keymaps = {
      ["<C-h>"] = false,
      ["<C-l>"] = false,
      ["gx"] = false,
      ["<C-x>"] = { "actions.select", opts = { horizontal = true } },
      ["<C-r>"] = "actions.refresh",
      ["go"] = "actions.open_external",
      ["q"] = { "actions.close", mode = "n" },
    },
    view_options = { show_hidden = true },
    float = { padding = 8, border = "rounded", max_width = 200 },
    preview_win = { update_on_cursor_moved = true },
    -- Moving a file through oil tells the LSP, so imports that referenced it
    -- are rewritten instead of silently breaking. This is the thing a file
    -- tree cannot do.
    lsp_file_methods = { enabled = true, timeout_ms = 1000, autosave_changes = true },
  },
}
