-- Covers UC-1 (open), UC-2 (write-then-close sends), UC-4 (blank aborts),
-- UC-5 (:q! aborts), UC-6 (seeding), UC-8 (failed send preserves the draft).
local t = dofile("tests/helper.lua")
local composer = require("ai.composer")

-- Capture sends instead of driving a real agent. The indirection exists in the
-- module for exactly this reason.
local sent = {}
local fail_next = false
composer._send = function(text, opts)
  if fail_next then
    fail_next = false
    if opts and opts.on_error then opts.on_error("simulated failure") end
    return
  end
  sent[#sent + 1] = { text = text, opts = opts }
end

local function close(force)
  vim.cmd(force and "bwipeout!" or "bwipeout")
end

-- UC-1: opens a usable composer buffer.
composer.open()
local buf = vim.api.nvim_get_current_buf()
t.eq(vim.bo[buf].buftype, "acwrite", "UC-1: composer buffer is acwrite")
t.eq(vim.bo[buf].swapfile, false, "UC-1: composer has no swapfile")
t.ok(vim.api.nvim_buf_is_valid(buf), "UC-1: composer buffer is valid")
-- markdown + acwrite would otherwise opt this buffer into conform's
-- markdown -> prettier rule on :w, rewriting the prompt before it is sent.
t.eq(vim.b[buf].autoformat, false, "UC-1: composer opts out of format-on-save")
close(true)

-- A prompt must survive :w byte for byte. Markdown formatters normalise list
-- markers and reflow paragraphs; neither may happen to a prompt.
composer.open()
local picky = { "*  loose list marker", "", "a line that a formatter might well decide to rewrap because it is long" }
vim.api.nvim_buf_set_lines(0, 0, -1, false, picky)
vim.cmd("write")
t.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), picky, "UC-2: :w does not reformat the prompt")
close(true)
sent = {}

-- UC-4: an empty composer sends nothing even when written.
composer.open()
vim.cmd("write")
close(true)
t.eq(#sent, 0, "UC-4: empty composer sends nothing")

-- UC-4: whitespace only is still empty.
composer.open()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "   ", "", "\t" })
vim.cmd("write")
close(true)
t.eq(#sent, 0, "UC-4: whitespace-only composer sends nothing")

-- UC-2 + UC-7: written then closed sends once, intact, and submits.
composer.open()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line one", "line two" })
vim.cmd("write")
close(true)
t.eq(#sent, 1, "UC-2: written composer sends exactly once")
t.eq(sent[1].text, "line one\nline two", "UC-7: multi-line text is sent as one payload")
t.eq(sent[1].opts.submit, true, "UC-2: send requests submission")

-- UC-5: never written means never sent, which is what :q! does.
composer.open()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "discard me" })
close(true)
t.eq(#sent, 1, "UC-5: unwritten composer sends nothing")

-- UC-6: seeding puts text in the buffer.
composer.open("seeded text")
t.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "seeded text" }, "UC-6: seed lands in the buffer")
close(true)

-- The window must be escapable. <C-c> discards without sending, and it is
-- bound in Normal mode only: Insert-mode <C-c> means "leave Insert" globally
-- (lua/mappings.lua:61) and that meaning has to survive.
composer.open()
local escape_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abandon this" })

local normal_map = vim.fn.maparg("<C-c>", "n", false, true)
t.eq(normal_map.buffer, 1, "<C-c> is bound buffer-locally in Normal mode")

local insert_map = vim.fn.maparg("<C-c>", "i", false, true)
t.eq(insert_map.buffer, 0, "<C-c> in Insert mode is still the global exit-insert map")

t.ok(type(normal_map.callback) == "function", "<C-c> runs a callback")
normal_map.callback()
t.ok(not vim.api.nvim_buf_is_valid(escape_buf), "<C-c> closes the composer")
t.eq(#sent, 1, "<C-c> sends nothing")

-- UC-8: a failed send preserves the draft for recovery.
fail_next = true
composer.open()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "precious draft" })
vim.cmd("write")
close(true)
t.eq(#sent, 1, "UC-8: the failed send did not count as delivered")
composer.open()
t.eq(
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  { "precious draft" },
  "UC-8: reopening restores the draft that failed to send"
)
close(true)

-- The restored draft must not come back a second time once it is dealt with.
composer.open()
t.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" }, "recovered draft is consumed once")
close(true)

t.done()
