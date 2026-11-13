-- lazy.nvim's default here is `lazy = true` (lua/config/lazy.lua `defaults`), so a
-- spec without a trigger never loads on its own. The LSP stack, completion and
-- reference highlighting therefore hang off their first use, and the two that
-- must exist from the first frame say `lazy = false` explicitly. An earlier
-- `default =` typo was silently ignored and loaded all of these at startup.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")

local function loaded(name)
  local plugin = Config.plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end

t.eq(Config.options.defaults.lazy, true, "plugins are lazy unless a spec says otherwise")

-- This spec starts without a file, the dashboard case.
for _, name in ipairs({ "mason-lspconfig.nvim", "nvim-lspconfig", "blink.cmp", "vim-illuminate" }) do
  t.ok(not loaded(name), name .. " stays unloaded until it is first used")
end
t.ok(loaded("lualine.nvim"), "lualine is loaded for the first frame")
-- Both are declared always, whatever lua/ai/config.lua's providers list, and
-- wait for their first command or key: the facade's mappings (lua/ai/init.lua)
-- and :AI define no plugin load.
for _, name in ipairs({ "claudecode.nvim", "codecompanion.nvim" }) do
  t.ok(require("lazy.core.config").plugins[name] ~= nil and not loaded(name), name .. " is declared and stays unloaded at startup")
end
-- A spec made conditional would be pruned from the lock and listed for
-- :Lazy clean; declared, claudecode's commands are its lazy triggers.
t.eq(#Config.to_clean, 0, "nothing is left for :Lazy clean to delete")
t.eq(vim.fn.exists(":ClaudeCode"), 2, ":ClaudeCode is a lazy trigger")
-- CodeDiff's setup loads its native library (and would download it), so it
-- waits for :CodeDiff or a <leader>g key. Nothing of the review loop loads
-- or runs git before its first use either.
t.ok(Config.plugins["codediff.nvim"] ~= nil and not loaded("codediff.nvim"), "codediff.nvim is declared and stays unloaded at startup")
for _, module in ipairs({ "codediff", "util.codediff", "util.codediff_actions", "util.baseline",
  "ai.review", "ai.review.rounds", "ai.review.feedback" }) do
  t.eq(package.loaded[module], nil, module .. " is not loaded at startup")
end
t.ok(loaded("mason.nvim"), "mason is loaded at startup")
t.ok(vim.tbl_contains(vim.split(vim.env.PATH, ":", { plain = true }), vim.fn.stdpath("data") .. "/mason/bin"),
  "mason/bin is on PATH before any terminal can spawn")
t.ok(vim.fn.exists(":Mason") == 2, ":Mason works from the dashboard")

vim.api.nvim_feedkeys(vim.keycode(":<Esc>"), "x", false)
t.ok(loaded("blink.cmp"), "entering the command line loads completion")

vim.cmd.edit("lua/plugins/coding/lsp.lua")
for _, name in ipairs({ "mason-lspconfig.nvim", "nvim-lspconfig", "vim-illuminate" }) do
  t.ok(loaded(name), name .. " loads on the first file read")
end
t.ok(not loaded("codediff.nvim"), "reading a file in a repository does not load CodeDiff")

if vim.fn.executable("lua-language-server") == 1 then
  t.ok(vim.wait(10000, function()
    return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0
  end, 50), "the server attaches to the buffer that loaded the LSP stack")
else
  print("skip - lua-language-server is not installed")
end

-- illuminate refreshes on CursorMoved, so loading on BufReadPost must still
-- reach the buffer that triggered it.
vim.fn.search("\\<opts\\>")
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
local ns = vim.api.nvim_create_namespace("illuminate.highlight")
t.ok(vim.wait(5000, function()
  return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) > 0
end, 50), "references highlight in the first buffer read")

t.done()
