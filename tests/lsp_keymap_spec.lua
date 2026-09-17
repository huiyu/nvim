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

t.done()
