local t = dofile("tests/helper.lua")

-- The LSP keys are buffer-local: they only exist after a real client attaches,
-- so this spec starts a real lua_ls against this repository rather than
-- asserting against the spec table. A startup check cannot see any of them.
vim.cmd("edit lua/util/cwd.lua")
local attached = vim.wait(30000, function()
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end, 200)

if not attached then
  -- Mason may not have lua_ls installed yet on a fresh clone. Say so instead of
  -- failing every assertion below, which would read as a broken keymap.
  print("SKIP - no LSP client attached to lua/util/cwd.lua (is lua_ls installed?)")
  t.done()
  return
end

local function mapping(lhs, mode)
  return vim.fn.maparg(lhs, mode or "n", false, true)
end

-- Every jump that starts from the symbol under the cursor lives on `g`. These
-- are the keys AGENTS.md pins; a rename here is a documentation change too.
for lhs, want in pairs({
  gd = "[LSP] Goto Definition",
  gr = "[LSP] References",
  gb = "[LSP] Goto Implementation (body)",
  gy = "[LSP] Goto Type Definition",
  gD = "[LSP] Goto Declaration",
  gC = "[LSP] Incoming calls",
  gK = "[LSP] Signature Help",
  K  = "[LSP] Hover",
}) do
  local m = mapping(lhs)
  t.eq(m.desc, want, lhs .. " is " .. want)
  t.eq(m.buffer, 1, lhs .. " is buffer-local, so plain buffers keep the builtin")
end

-- Without <nowait> every `gr` press waits out 'timeoutlen' (1s by default),
-- because Nvim's default grr/gri/grt/gra/grn/grx are longer candidates. This is
-- the whole reason References is reachable at speed.
t.eq(mapping("gr").nowait, 1, "gr fires immediately instead of waiting for gr*")

-- <nowait> costs the gr* defaults their second key inside an LSP buffer, so each
-- one needs a shorter equivalent here. ,c exists specifically to replace grx.
for lhs, want in pairs({
  [",a"] = "[LSP] Code action",     -- replaces gra
  [",r"] = "[LSP] Rename",          -- replaces grn
  [",c"] = "[LSP] Run codelens",    -- replaces grx, which has no other route
}) do
  t.eq(mapping(lhs).desc, want, lhs .. " covers a gr* default that nowait hides")
end

-- Vim's own g keys must survive: gi/gI insert, gc comments. Implementation and
-- incoming calls took free letters precisely so these stayed builtin.
t.eq(mapping("gI"), {}, "gI is still Vim's insert-at-column-1")
t.eq(mapping("gi"), {}, "gi is still Vim's resume-last-insert")

-- Nvim 0.11's defaults are not overridden, only shadowed inside LSP buffers.
for _, lhs in ipairs({ "grr", "gri", "grt", "gra", "grn", "grx" }) do
  t.eq(mapping(lhs).buffer, 0, lhs .. " remains Nvim's own global mapping")
end

-- The fuzzy symbol pickers take no starting symbol, so they stay on `;`.
t.eq(mapping(";s").desc, "[LSP] Symbol in buffer", ";s stays a fuzzy picker")
t.eq(mapping(";S").desc, "[LSP] Symbol in workspace", ";S stays a fuzzy picker")
t.eq(mapping(";c"), {}, ";c moved to gC: incoming calls needs a symbol to start from")

-- K is silent. Hovering a blank line is routine; noice used to filter out the
-- "No information available" notice it raises, and K now asks hover() not to
-- raise it. The unsilenced call first proves the server answers at that spot,
-- so the silence below is not just a slow server.
local notified = {}
local real_notify = vim.notify
vim.notify = function(msg) notified[#notified + 1] = tostring(msg) end
local blank
for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  if line == "" then blank = i; break end
end
vim.api.nvim_win_set_cursor(0, { blank, 0 })
-- Until its workspace is loaded, lua_ls answers every hover with a "Workspace
-- loading" document, which would open a popup instead.
local hover_params = vim.lsp.util.make_position_params(0, "utf-16")
for _ = 1, 60 do
  local replies = vim.lsp.buf_request_sync(0, "textDocument/hover", hover_params, 2000) or {}
  local reply = select(2, next(replies))
  if reply and reply.result == nil and reply.err == nil then break end
  vim.wait(500)
end
vim.lsp.buf.hover()
local answered = vim.wait(10000, function() return #notified > 0 end, 50)
t.ok(answered and notified[1] == "No information available",
  "an unsilenced hover on a blank line reports that it found nothing")
notified = {}
mapping("K").callback()
vim.wait(2000, function() return #notified > 0 end, 50)
t.eq(notified, {}, "K on a blank line raises no notification")
vim.notify = real_notify

-- <C-f>/<C-b> scroll an open hover from the code window (noice did this
-- before); with no popup they stay a page scroll. A plain float stands in for
-- the hover, tagged the way open_floating_preview tags one: the buffer var
-- naming the window, plus the hover focus_id as a window var.
local scroll_f, scroll_b = mapping("<C-f>"), mapping("<C-b>")
t.eq(scroll_f.desc, "[LSP] Scroll hover / page", "<C-f> is the hover/page scroll")
t.eq(scroll_f.buffer, 1, "<C-f> is buffer-local, so plain buffers keep the builtin")
t.eq(scroll_f.callback(), "<C-f>", "<C-f> without a popup is the usual page scroll")

-- The diagnostic float that ]d / [d open goes through open_floating_preview
-- too, so it also sets b:lsp_floating_preview. It must not capture the key:
-- scrolling never moves the cursor, so it would stay open and swallow every
-- later page scroll.
local diag_ns = vim.api.nvim_create_namespace("lsp_keymap_spec")
local diag_line = vim.api.nvim_win_get_cursor(0)[1] - 1
vim.diagnostic.set(diag_ns, 0, {
  { lnum = diag_line, col = 0, message = "spec diagnostic", severity = vim.diagnostic.severity.WARN },
})
local _, diag_float = vim.diagnostic.open_float({ scope = "line" })
t.ok(diag_float and vim.b.lsp_floating_preview == diag_float,
  "the diagnostic float is recorded as the buffer's preview float")
t.eq(scroll_f.callback(), "<C-f>", "<C-f> pages the buffer while a diagnostic float is open")
t.eq(scroll_b.callback(), "<C-b>", "<C-b> pages the buffer while a diagnostic float is open")
if diag_float and vim.api.nvim_win_is_valid(diag_float) then vim.api.nvim_win_close(diag_float, true) end
vim.diagnostic.reset(diag_ns, 0)

local doc = vim.api.nvim_create_buf(false, true)
local doc_lines = {}
for i = 1, 60 do doc_lines[i] = "line " .. i end
vim.api.nvim_buf_set_lines(doc, 0, -1, false, doc_lines)
local popup = vim.api.nvim_open_win(doc, false,
  { relative = "cursor", row = 1, col = 0, width = 20, height = 5 })
vim.b.lsp_floating_preview = popup
vim.w[popup]["textDocument/hover"] = vim.api.nvim_get_current_buf()
local code_win, code_top = vim.api.nvim_get_current_win(), vim.fn.line("w0")
local function topline() return vim.fn.getwininfo(popup)[1].topline end
t.eq(scroll_f.callback(), "", "<C-f> with a popup open consumes the key")
t.ok(vim.wait(2000, function() return topline() > 1 end, 20), "<C-f> scrolls the popup down")
local scrolled = topline()
t.eq(scroll_b.callback(), "", "<C-b> with a popup open consumes the key")
t.ok(vim.wait(2000, function() return topline() < scrolled end, 20), "<C-b> scrolls the popup back up")
t.eq(vim.api.nvim_get_current_win(), code_win, "focus stays in the code window")
t.eq(vim.fn.line("w0"), code_top, "the code window itself does not scroll")
vim.api.nvim_win_close(popup, true)
t.eq(scroll_b.callback(), "<C-b>", "<C-b> after the popup closed is a page scroll again")

t.done()
