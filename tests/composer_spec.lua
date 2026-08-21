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

local escape_win = vim.api.nvim_get_current_win()
t.ok(vim.api.nvim_win_is_valid(escape_win), "the composer float exists before discarding")

t.ok(type(normal_map.callback) == "function", "<C-c> runs a callback")
normal_map.callback()
t.ok(not vim.api.nvim_buf_is_valid(escape_buf), "<C-c> wipes the composer buffer")
-- The window has to go too. Deleting only the buffer left the float on screen
-- showing an unrelated buffer.
t.ok(not vim.api.nvim_win_is_valid(escape_win), "<C-c> closes the composer window")
t.eq(#sent, 1, "<C-c> sends nothing")

-- Image attachment. The clipboard is real, so snapshot it and put it back.
if vim.uv.os_uname().sysname == "Darwin" then
  local clipboard = require("ai.clipboard")
  local fixture = vim.fn.fnamemodify("tests/fixtures/pixel.png", ":p")

  local saved_text
  if not clipboard.has_image() then saved_text = vim.fn.getreg("+") end

  local pcall_ok = pcall(function()
    composer.open()
    local img_buf = vim.api.nvim_get_current_buf()
    t.ok(vim.fn.maparg("<C-v>", "i", false, true).buffer == 1,
      "<C-v> attaches an image from Insert mode, matching the TUI's own key")

    -- Nothing on the clipboard: must decline, not stage an empty file.
    vim.fn.setreg("+", "just text")
    vim.fn.maparg("<C-v>", "n", false, true).callback()
    t.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" },
      "a text clipboard attaches nothing")

    -- With an image: a placeholder appears and the file is staged.
    clipboard.restore_image(fixture)
    vim.fn.maparg("<C-v>", "n", false, true).callback()
    local body = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    t.ok(body:find("[image 1]", 1, true) ~= nil, "an attached image leaves a placeholder")

    sent = {}
    vim.cmd("write")
    close(true)
    t.eq(#sent, 1, "a prompt with an image is sent")
    t.ok(sent[1].opts.images ~= nil and #sent[1].opts.images == 1,
      "the staged image path travels with the send")

    -- Staging survives a yank, which is the whole reason for the temp file:
    -- clipboard=unnamedplus would otherwise have overwritten the screenshot.
    t.ok(vim.uv.fs_stat(sent[1].opts.images[1]) ~= nil,
      "the staged image file exists at send time")
    vim.fn.delete(sent[1].opts.images[1])

    -- A discarded composer must not leave staged images behind.
    clipboard.restore_image(fixture)
    composer.open()
    vim.fn.maparg("<C-v>", "n", false, true).callback()
    local orphan = vim.fn.glob(clipboard.staging_dir() .. "/*.png", false, true)[1]
    t.ok(orphan ~= nil, "discarding stages a file first")
    composer.discard(vim.api.nvim_get_current_buf())
    t.ok(orphan == nil or vim.uv.fs_stat(orphan) == nil,
      "discarding cleans up its staged images")
    t.ok(img_buf ~= nil, "image buffer was tracked")
  end)

  if saved_text then vim.fn.setreg("+", saved_text) end
  vim.fn.delete(clipboard.staging_dir(), "rf")
  t.ok(pcall_ok, "image attachment path did not raise")
end

sent = {}

-- UC-8: a failed send preserves the draft for recovery.
fail_next = true
composer.open()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "precious draft" })
vim.cmd("write")
close(true)
t.eq(#sent, 0, "UC-8: a failed send is not recorded as delivered")
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
