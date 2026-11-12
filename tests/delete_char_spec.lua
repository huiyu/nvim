local t = dofile("tests/helper.lua")

-- Normal-mode x deletes into the black hole register (lua/config/keymaps.lua). Under
-- clipboard=unnamedplus a plain x otherwise replaced the system clipboard and
-- pushed a one-character entry onto the yanky ring.
--
-- TextYankPost is what both of those follow: yanky records the ring from it,
-- and it fires for every delete except one into the black hole. The clipboard
-- provider cannot be the witness: while Nvim is still starting up (where -c
-- runs specs) an implicit clipboard write is held back and never reaches it.
--
-- A stand-in provider still replaces the real one, so a put cannot read the
-- user's clipboard and a write that does get through cannot replace it.
local fake = { ["+"] = { { "" }, "v" }, ["*"] = { { "" }, "v" } }
vim.g.clipboard = {
  name = "delete-char-spec",
  copy = {
    ["+"] = function(lines, regtype) fake["+"] = { lines, regtype } end,
    ["*"] = function(lines, regtype) fake["*"] = { lines, regtype } end,
  },
  paste = {
    ["+"] = function() return fake["+"] end,
    ["*"] = function() return fake["*"] end,
  },
}
vim.g.loaded_clipboard_provider = nil
vim.cmd("runtime autoload/provider/clipboard.vim")
t.eq(vim.fn["provider#clipboard#Executable"](), "delete-char-spec",
  "the stand-in clipboard provider is active")

local yanks = {}
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() yanks[#yanks + 1] = vim.v.event.regname end,
})

local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
end
local function line() return vim.api.nvim_get_current_line() end
local function reset(text)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  yanks = {}
end

local m = vim.fn.maparg("x", "n", false, true)
t.eq(m.desc, "Delete character (no yank)", "x has a discoverable description")
t.eq(m.expr, 1, "x picks its register when pressed")
t.eq(vim.fn.maparg("x", "x", false, true), {}, "Visual x stays a cut")
t.eq(vim.o.clipboard, "unnamedplus", "the default register is the system clipboard")

vim.cmd.enew()

-- The control: an ordinary delete is seen.
reset("abc")
press("dl")
t.eq(#yanks, 1, "dl reaches TextYankPost")

reset("abcdef")
press("x")
t.eq(line(), "bcdef", "x deletes the character under the cursor")
press("2x")
t.eq(line(), "def", "a count still applies")
press(".")
t.eq(line(), "f", ". repeats the black-hole delete")
t.eq(yanks, {}, "x neither yanks nor feeds the yank ring or the clipboard")

-- A named register is a deliberate choice and still applies.
reset("abc")
press('"ax')
t.eq(vim.fn.getreg("a"), "a", '"ax still deletes into register a')
t.eq(yanks, { "a" }, '"ax is the one x that yanks')

-- From here the unnamed register is the default. The swap needs it: under
-- unnamedplus the held-back write would leave `p` nothing to put.
vim.o.clipboard = ""

-- xp no longer swaps two characters (nothing was yanked); dlp does.
reset("ab")
press("dlp")
t.eq(line(), "ba", "dlp swaps two characters")

-- The unnamed register is spared as well.
reset("abc")
vim.fn.setreg('"', "kept")
press("x")
t.eq(vim.fn.getreg('"'), "kept", "x leaves the unnamed register alone")
t.eq(yanks, {}, "x does not yank without a clipboard either")

-- yanky's ring is built from the events above, so it does not grow either.
require("lazy").load({ plugins = { "yanky.nvim" } })
local history = require("yanky.history")
vim.o.clipboard = "unnamedplus"
reset("abc")
local before = #history.all()
press("x")
t.eq(#history.all(), before, "x adds nothing to the yanky ring")
press("dl")
t.eq(#history.all(), before + 1, "dl does (the ring is listening)")

t.done()
