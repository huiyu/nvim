-- The LSP stack and vim-illuminate load on BufReadPre/BufReadPost
-- (tests/lazy_loading_spec.lua), which an editing buffer that never read a
-- file does not fire: `:enew` followed by `:setf lua`, or `nvim -`. Such a
-- buffer loads them on its first filetype; a panel's nofile buffer does not.
-- Its own process, because the first file read loads everything for good.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")

local function loaded(name)
  local plugin = Config.plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end

local panel = vim.api.nvim_create_buf(false, true)
vim.bo[panel].filetype = "lua"
t.ok(not loaded("mason-lspconfig.nvim") and not loaded("vim-illuminate"),
  "a filetype on a nofile panel loads neither")

vim.cmd.enew()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local foo = 1", "print(foo)" })
vim.bo.filetype = "lua"
for _, name in ipairs({ "mason-lspconfig.nvim", "nvim-lspconfig", "vim-illuminate" }) do
  t.ok(loaded(name), name .. " loads on a scratch buffer's first filetype")
end

if vim.fn.executable("lua-language-server") == 1 then
  t.ok(vim.wait(10000, function()
    return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0
  end, 50), "the server attaches to the scratch buffer itself")
  t.ok(vim.fn.maparg("gd", "n", false, true).buffer == 1, "the scratch buffer gets the [LSP] mappings")
else
  print("skip - lua-language-server is not installed")
end

t.done()
