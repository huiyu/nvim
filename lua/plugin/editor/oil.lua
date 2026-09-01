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
    vim.api.nvim_create_autocmd("BufNew", {
      group = vim.api.nvim_create_augroup("oil_directory_buffers", { clear = true }),
      callback = function(ev)
        if ev.file ~= "" and vim.fn.isdirectory(ev.file) == 1 then
          vim.schedule(function() require("oil").open(ev.file) end)
        end
      end,
      desc = "Open a directory buffer in oil",
    })

    -- A directory named on the command line has its buffer created before the
    -- autocmd above exists, so `nvim lua/` needs its own check.
    local first = vim.fn.argc() > 0 and vim.fn.argv(0) or nil
    if type(first) == "string" and vim.fn.isdirectory(first) == 1 then
      vim.schedule(function() require("oil").open(first) end)
    end
  end,
  keys = {
    { ";o", function() require("oil").open_float(nil, { preview = {} }) end,
      desc = "Oil file manager (float)" },
    -- oil's own convention, and the reason it is worth the shadowing: `-`
    -- reaches the current file's directory in one key. It replaces the builtin
    -- "first non-blank of the previous line" motion, which `k^` already covers.
    { "-", function() require("oil").open() end, desc = "Oil: parent directory" },
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
      ["h"] = { "actions.parent", mode = "n" },
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
