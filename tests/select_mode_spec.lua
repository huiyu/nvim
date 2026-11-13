local t = dofile("tests/helper.lua")

-- A snippet placeholder is a Select-mode selection: vim.snippet selects it with
-- `v`, `o` and <C-g>, and blink.cmp expands through vim.snippet. The first
-- printable key typed there must replace the placeholder. A mapping made with
-- mode "v" (`:vmap`) covers Select mode as well as Visual, so `<` and `>`
-- indented the line instead, and a leading `,` or <Space> started a mapping
-- (`,f` formatted, ` yy` yanked, ` db` set a breakpoint). Visual keys here are
-- "x"; keys that ignore the selection (<leader>t, <leader>d but dw/dW) are
-- Normal only. Pinned three ways: typing into a real placeholder, the modes of
-- the keys that leaked, and no Select-mode mapping of this config on a
-- printable key at all.

local function map(lhs, mode)
  return vim.fn.maparg(lhs, mode, false, true)
end

---------------------------------------------------------------------------
-- Typing into a placeholder
---------------------------------------------------------------------------

local function type_into_placeholder(keys)
  pcall(vim.snippet.stop)
  -- A key that leaks opens what it maps to (`,F`: a grug-far split whose
  -- buffer raises on unload), so each case starts from one plain window and
  -- a regression reads as a FAIL per key rather than a spec error.
  vim.cmd("silent! only! | silent! enew!")
  vim.bo.buftype = "nofile"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "    x" })
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  -- "x" runs the typeahead to its end, the keys vim.snippet feeds to select
  -- the placeholder included, and leaves Select mode active.
  vim.api.nvim_feedkeys(vim.keycode("A<Cmd>lua vim.snippet.expand('f(${1:arg})')<CR>"), "nx", false)
  local before = vim.api.nvim_get_mode().mode
  -- "m": mappings apply, as they would to typed keys.
  vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
  local line = vim.api.nvim_get_current_line()
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  pcall(vim.snippet.stop)
  return before, line
end

-- Everything is typed first and asserted after: an assertion printed between
-- two typeahead runs loses its newline in the headless output.
local typed = {}
-- One key per kind that leaked; the scan at the end holds every other lhs.
for _, keys in ipairs({
  "Z",            -- the control case: a plain letter
  "<",            -- Indent left (Visual)
  ",f",           -- Format
  " yy",          -- Yank selection to register
  " db",          -- Toggle breakpoint
}) do
  local before, line = type_into_placeholder(keys)
  typed[#typed + 1] = { keys = keys, before = before, line = line }
end

-- Visual mode keeps the keys.
vim.cmd("enew!")
vim.bo.buftype = "nofile"
vim.bo.shiftwidth = 2
vim.bo.expandtab = true
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("Vj>"), "mx", false)
local reselected = vim.api.nvim_get_mode().mode
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
local indented = vim.api.nvim_buf_get_lines(0, 0, -1, false)

for _, case in ipairs(typed) do
  local name = case.keys:gsub(" ", "<Space>")
  t.eq(case.before, "s", name .. ": the expanded snippet's placeholder is in Select mode")
  t.eq(case.line, "    xf(" .. case.keys .. ")",
    name .. " typed first replaces the placeholder (no mapping, no indent)")
end
t.eq(indented, { "  a", "  b" }, "Visual > still indents the selection")
t.eq(reselected, "V", "and reselects it (>gv)")

---------------------------------------------------------------------------
-- The modes of the keys that leaked
---------------------------------------------------------------------------

-- Act on the selection: Visual ("x"), never Select.
for lhs, desc in pairs({
  ["<"] = "Indent left",
  [">"] = "Indent right",
  ["<leader>yy"] = "Yank selection to register",
  ["<leader>yc"] = "Yank selection to clipboard",
  [",f"] = "Format",
  [",F"] = "Search and replace",
  ["<leader>dw"] = "Evaluate selection",
  ["<leader>dW"] = "Add watch expression…",
  ["<C-a>"] = "Increment",
  ["<C-x>"] = "Decrement",
  ["g<C-a>"] = "Increment (progressive)",
  ["g<C-x>"] = "Decrement (progressive)",
}) do
  local visual = map(lhs, "x")
  t.eq({ visual.desc, visual.mode }, { desc, "x" }, lhs .. " is a Visual-mode (x) key")
end
-- dw evaluates the selection in Visual mode and <cexpr> in Normal mode, and
-- each popup says which.
t.eq(map("<leader>dw", "n").desc, "Evaluate expression", "<leader>dw names its Normal-mode input")

-- Ignore the selection: Normal only. dw/dW above are the debug keys that read it.
for _, suffix in ipairs({
  "dB", "db", "dq", "dx", "dc", "da", "dC", "dg", "di", "dj", "dk", "dl", "do", "dO", "dP", "dr", "dt",
  "tm", "tM", "tf", "tF", "ts", "to", "tx",
}) do
  local lhs = "<leader>" .. suffix
  t.ok(next(map(lhs, "n")) ~= nil, lhs .. " is mapped in Normal mode")
  t.eq(map(lhs, "x"), {}, lhs .. " is not mapped in Visual mode (it reads no selection)")
end

-- which-key groups: "v" would add Select mode, where the group alone makes
-- <Space> a trigger inside a placeholder.
local Spec = require("config.whichkey_spec")
local groups, selecting = {}, {}
for _, entry in ipairs(Spec.spec) do
  local modes = type(entry.mode) == "table" and entry.mode or { entry.mode or "n" }
  if vim.tbl_contains(modes, "v") or vim.tbl_contains(modes, "s") then
    selecting[#selecting + 1] = tostring(entry[1])
  end
  if entry.group then groups[entry[1]] = entry.mode end
end
t.eq(selecting, {}, "no which-key spec entry is declared for Select mode (\"v\" or \"s\")")
for lhs, want in pairs({
  ["<leader>a"] = { "n", "x" }, ["<leader>d"] = { "n", "x" }, ["<leader>g"] = { "n", "x" },
  ["<leader>G"] = { "n", "x" }, ["<leader>y"] = { "n", "x" },
  ["<leader>t"] = "n", ["<leader>m"] = "n",
}) do
  t.eq(groups[lhs], want, lhs .. " group modes")
end

---------------------------------------------------------------------------
-- No Select-mode mapping of this config on a printable key
---------------------------------------------------------------------------

local config_dirs = {}
for _, dir in ipairs({ vim.fn.stdpath("config"), vim.fn.getcwd() }) do
  local real = vim.uv.fs_realpath(dir)
  if real then config_dirs[#config_dirs + 1] = real .. "/" end
end

-- "config": made by this config -- a callback defined under it, a lazy.nvim
-- `keys` stub (every keys spec here is this config's), or a string rhs, which
-- carries no file (Nvim's own Select-mode defaults all have callbacks).
local function origin(m)
  if m.callback then
    local src = debug.getinfo(m.callback, "S").source or ""
    if src:sub(1, 1) ~= "@" then return "config" end
    local path = vim.uv.fs_realpath(src:sub(2)) or src:sub(2)
    if path:find("/lazy/core/handler/keys.lua", 1, true) then return "config" end
    for _, dir in ipairs(config_dirs) do
      if vim.startswith(path, dir) then return "config" end
    end
    return "other: " .. path
  end
  if (m.sid or 0) > 0 then
    local info = vim.fn.getscriptinfo({ sid = m.sid })[1]
    local path = info and (vim.uv.fs_realpath(info.name) or info.name) or ""
    for _, dir in ipairs(config_dirs) do
      if vim.startswith(path, dir) then return "config" end
    end
    return "other: " .. path
  end
  return "config"
end

-- Printable: what Select mode would type over the placeholder. <Space> and
-- `<` count; <Tab>, <C-…> and special keys (K_SPECIAL, 0x80) do not.
local function printable(lhs)
  local byte = vim.keycode(lhs):byte(1)
  return byte ~= nil and byte >= 0x20 and byte ~= 0x7f and byte ~= 0x80
end

vim.cmd("enew!")
local leaks = {}
local maps = vim.api.nvim_get_keymap("s")
vim.list_extend(maps, vim.api.nvim_buf_get_keymap(0, "s"))
for _, m in ipairs(maps) do
  if printable(m.lhs) and origin(m) == "config" then
    leaks[#leaks + 1] = ("%s %s (%s)"):format(m.mode, vim.fn.keytrans(vim.keycode(m.lhs)), m.desc or m.rhs or "")
  end
end
table.sort(leaks)
t.eq(leaks, {}, "no mapping of this config is reachable in Select mode on a printable key")

---------------------------------------------------------------------------
-- neotest's summary panel: g? is help, as in the other panels; ? stays
---------------------------------------------------------------------------

local neotest = require("lazy.core.config").plugins["neotest"]
local opts = neotest and require("lazy.core.plugin").values(neotest, "opts", false) or {}
t.eq(vim.tbl_get(opts, "summary", "mappings", "help"), { "?", "g?" },
  "neotest summary help is on ? and g?")

t.done()
