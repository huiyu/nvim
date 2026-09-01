-- Text objects and the which-key entries that advertise them.
--
-- mini.ai maps `i` and `a` as one expr key each and reads the object letter
-- itself, so which-key cannot see the objects it adds: after `di` the popup
-- listed the builtin objects and treesitter-textobjects' `f`/`c`, but not
-- mini.ai's `a` (argument) or `o` (block). The manual promises "press d, then
-- i, and the menu lists the rest", so lua/whichkey_spec.lua carries desc-only
-- entries for every object the manual documents. which-key keeps spec entries
-- in its own trie and never calls vim.keymap.set, so this asserts against the
-- table (see AGENTS.md) rather than maparg().
local t = dofile("tests/helper.lua")

-- VeryLazy never fires headless; load what the objects need explicitly.
vim.cmd("Lazy! load mini.ai nvim-treesitter-textobjects")

-- UC-2: every documented syntax-aware object has a which-key entry in both
-- Visual and Operator-pending mode, worded like which-key's own presets
-- ("inner word" / "word with ws") rather than like the plugin's mapping desc.
local want = {
  ["if"] = "inner function",
  af = "function",
  ic = "inner class",
  ac = "class",
  ia = "inner argument",
  aa = "argument with separator",
  io = "inner block/conditional/loop",
  ao = "block/conditional/loop",
}
local found = {}
for _, entry in ipairs(require("whichkey_spec")) do
  if type(entry[1]) == "string" and want[entry[1]] and entry.desc then
    local modes = type(entry.mode) == "table" and entry.mode or { entry.mode }
    found[entry[1]] = { desc = entry.desc, modes = modes }
  end
end
for _, lhs in ipairs({ "if", "af", "ic", "ac", "ia", "aa", "io", "ao" }) do
  local got = found[lhs]
  t.ok(got ~= nil, "UC-2: whichkey_spec describes " .. lhs)
  if got then
    t.eq(got.desc, want[lhs], "UC-2: " .. lhs .. " uses the shared wording")
    t.ok(vim.tbl_contains(got.modes, "o") and vim.tbl_contains(got.modes, "x"),
      "UC-2: " .. lhs .. " is listed after an operator and in Visual")
  end
end

-- UC-R2: the entries are descriptions only. The objects themselves still come
-- from mini.ai / treesitter-textobjects, so `daa` keeps taking the separator.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "lua"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "foo(bar, baz)" })
-- A live session keeps the tree parsed through the highlighter; headless it
-- is parsed on demand, and mini.ai reports "no textobject" on an unparsed one.
vim.treesitter.get_parser(buf, "lua"):parse(true)
vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- on "baz"
vim.cmd("normal daa")
t.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "foo(bar)" },
  "UC-R2: daa still deletes the argument together with its comma")

t.done()
