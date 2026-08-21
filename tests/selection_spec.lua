-- Covers UC-6 (composer seeding) and UC-R2 (<leader>as behaviour preserved).
local t = dofile("tests/helper.lua")
local sel = require("ai.selection")

-- draft() reads the *live* visual selection, so it has to be called from inside
-- Visual mode. Driving it through an x-mode mapping is also the production path:
-- <leader>as is an x-mode mapping (lua/ai/init.lua:63).
-- Checked first, while the session is still cleanly in Normal mode. Leaving
-- Visual mode afterwards is unreliable headless, and the guard being wrong is
-- exactly what would let the composer seed a draft the user never selected.
do
  t.eq(vim.fn.mode(), "n", "spec starts in Normal mode")
  local none, err = sel.draft()
  t.ok(none == nil, "no visual selection returns nil")
  t.ok(type(err) == "string", "no visual selection returns a reason")
end

local captured
vim.keymap.set("x", "<F13>", function() captured = { sel.draft() } end, {})

local function draft_over(lines, opts)
  opts = opts or {}
  captured = nil
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if opts.filetype then vim.bo[buf].filetype = opts.filetype end
  if opts.path then
    vim.api.nvim_buf_set_name(buf, opts.path)
    vim.bo[buf].modified = opts.modified or false
  end
  vim.api.nvim_feedkeys(vim.keycode("ggVG<F13>"), "x", false)
  return captured and captured[1], captured and captured[2], captured and captured[3], buf
end

-- An unsaved buffer has no path to @-mention, so the literal text must travel.
local draft = draft_over({ "alpha", "beta" }, { filetype = "lua" })
t.ok(type(draft) == "string", "UC-6: draft() returns a string for an unsaved buffer")
t.ok(draft and draft:find("alpha", 1, true) ~= nil, "UC-6: draft carries the selected text")
t.ok(draft and draft:find("beta", 1, true) ~= nil, "UC-6: draft carries every selected line")
t.ok(draft and draft:find("@", 1, true) == nil, "UC-6: unsaved buffer produces no @-mention")
t.ok(draft and draft:find("````lua", 1, true) ~= nil, "UC-6: text is fenced with the filetype")

-- A saved, unmodified file becomes an @-mention with the line range, and the
-- trailing space matters: the TUI puts the cursor right after it.
local tmp = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "one", "two", "three" }, tmp)
local mention = draft_over({ "one", "two", "three" }, { path = tmp, filetype = "lua" })
t.ok(mention and mention:find("^@") ~= nil, "UC-R2: saved buffer produces an @-mention")
t.ok(mention and mention:find("lines 1%-3") ~= nil, "UC-R2: mention carries the line range")
t.ok(mention and mention:sub(-1) == " ", "UC-R2: mention keeps its trailing space")

-- A modified buffer must fall back to the literal text and say why.
-- A second path is needed: Nvim rejects two buffers sharing a name (E95).
local tmp2 = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "one", "two" }, tmp2)
local dirty, _, notice = draft_over({ "one", "two" }, { path = tmp2, modified = true })
t.ok(dirty and dirty:find("@", 1, true) == nil, "UC-R2: modified buffer falls back to literal text")
t.ok(type(notice) == "string", "UC-R2: modified buffer returns a notice for the caller")

vim.fn.delete(tmp)
vim.fn.delete(tmp2)
t.done()
