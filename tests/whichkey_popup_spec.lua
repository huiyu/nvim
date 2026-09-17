local t = dofile("tests/helper.lua")

-- Two things are under test here.
--
-- The section layout is declared in lua/whichkey_spec.lua and read by
-- lua/plugin/editor/whichkey.lua. A suffix listed there that maps to nothing is
-- dead weight nobody would notice, so every declared key is resolved against a
-- real mapping.
--
-- The headings themselves are drawn by replacing which-key's `View.sort`. That
-- is the only place this config depends on plugin internals, and it fails
-- silently by design, so it gets asserted rather than trusted.

-- which-key loads on VeryLazy, which a headless session never reaches.
require("lazy").load({ plugins = { "which-key.nvim" } })

local ok_view, View = pcall(require, "which-key.view")
if not ok_view then
  print("SKIP - which-key is not installed")
  t.done()
  return
end

local Spec = require("whichkey_spec")

-- A declared suffix counts as live if any of these holds. Spec entries that
-- carry an RHS (";a" -> "<C-^>") stay inside which-key's own trie rather than
-- becoming a mapping maparg can see, and the g/, sections are LSP keys that
-- only exist once a client attaches -- neither is a dead key.
local spec_lhs = {}
for _, entry in ipairs(Spec.spec) do
  if type(entry[1]) == "string" then
    spec_lhs[vim.keycode(entry[1])] = true
  end
end

---------------------------------------------------------------------------
-- The declaration matches reality
---------------------------------------------------------------------------

local declared_total = 0
for prefix, list in pairs(Spec.sections) do
  for _, section in ipairs(list) do
    t.ok(type(section[1]) == "string" and section[1] ~= "",
      ("section under %q has a title"):format(prefix))
    t.ok(type(section.color) == "string" and section.color ~= "",
      ("section %q has a colour"):format(section[1]))
    for _, key in ipairs(section.keys) do
      declared_total = declared_total + 1
      local lhs = vim.keycode(prefix .. key)
      local live = next(vim.fn.maparg(lhs, "n", false, true)) ~= nil
        or spec_lhs[lhs]
        or prefix ~= ";"   -- buffer-local LSP keys, absent without a client
      t.ok(live, ("declared %s/%s resolves to a real key"):format(prefix, key))
    end
  end
end
t.ok(declared_total > 30, ("sections declare %d keys"):format(declared_total))

---------------------------------------------------------------------------
-- The headings render
---------------------------------------------------------------------------

---@param prefix string
---@return table[]
local function popup(prefix)
  local items = {}
  local pn = vim.fn.keytrans(vim.keycode(prefix))
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    -- keycode first: a raw lhs mixes literal "<C-A>" with real bytes.
    local keys = vim.fn.keytrans(vim.keycode(m.lhs))
    local suffix = keys:sub(1, #pn) == pn and keys:sub(#pn + 1) or nil
    -- first-level children only, the way a popup shows them
    if suffix and (#suffix == 1 or suffix:match("^<%w[%w-]*>$")) and m.desc then
      -- `keys` is what real items carry; the lookup keys off it.
      items[#items + 1] =
        { keys = keys, key = suffix, raw_key = m.lhs, desc = m.desc, keymap = m }
    end
  end
  View.sort(items)
  return items
end

--- The <leader> popup is nothing but group rows, which have no keymap at all.
--- Build it from the spec to prove sectioning works off `item.keys`.
---@return table[]
local function leader_popup()
  local items = {}
  for _, entry in ipairs(Spec.spec) do
    local lhs = type(entry[1]) == "string" and entry[1] or nil
    local suffix = lhs and lhs:match("^<leader>(.+)$")
    if entry.group and suffix and (#suffix == 1 or suffix:match("^<%a+>$")) then
      items[#items + 1] = {
        keys = vim.fn.keytrans(vim.keycode(lhs)),
        key = suffix, raw_key = lhs, desc = entry.group, group = true,
      }
    end
  end
  View.sort(items)
  return items
end

local function headings(items)
  local found = {}
  for _, item in ipairs(items) do
    if item.desc and item.desc:find("^── ") then
      found[#found + 1] = item.desc:gsub("^── ", "")
    end
  end
  return found
end

local semi = popup(";")
local semi_headings = headings(semi)

-- Headings must follow the declared order, not alphabetical order.
local expected = {}
for _, section in ipairs(Spec.sections[";"]) do
  expected[#expected + 1] = section[1]
end
local seen_order = {}
for _, title in ipairs(semi_headings) do
  seen_order[#seen_order + 1] = title
end
local ordered, cursor = true, 1
for _, title in ipairs(seen_order) do
  while cursor <= #expected and expected[cursor] ~= title do
    cursor = cursor + 1
  end
  if cursor > #expected then
    ordered = false
    break
  end
  cursor = cursor + 1
end
t.ok(ordered,
  ("; headings follow the declared order (%s)"):format(table.concat(seen_order, ", ")))
t.ok(#semi_headings >= 4,
  ("; popup gets headings (got %d)"):format(#semi_headings))

-- Headings are display-only. A row reaching key handling would be a bug.
for _, item in ipairs(semi) do
  if item.desc and item.desc:find("^── ") then
    t.eq(item.key, "", "heading " .. item.desc .. " has no key")
    t.eq(item.keymap, nil, "heading " .. item.desc .. " carries no keymap")
    t.ok(item.group == true, "heading " .. item.desc .. " renders with group highlight")
    t.ok((item.icon_hl or ""):find("^WhichKeyIcon"),
      "heading " .. item.desc .. " carries its section colour")
  end
end

t.ok(semi[1] and semi[1].desc and semi[1].desc:find("^── "),
  "the first row of the ; popup is a heading")
t.ok(semi[#semi] and not (semi[#semi].desc or ""):find("^── "),
  "the popup does not end on a dangling heading")

-- Keys inherit their section's colour, so heading and rows read as one block.
local painted = 0
for _, item in ipairs(semi) do
  if item.keymap and (item.icon_hl or ""):find("^WhichKeyIcon") then
    painted = painted + 1
  end
end
t.ok(painted >= 10, ("declared keys are painted with section colours (%d)"):format(painted))

-- Every declared prefix draws its headings.
for _, prefix in ipairs({ ",", "g", "<leader>g", "<leader>d" }) do
  local got = headings(popup(prefix))
  t.ok(#got >= 2, ("%s popup is sectioned (%s)"):format(prefix, table.concat(got, ", ")))
end

-- <leader> carries only group rows, which have no keymap: sectioning them
-- depends on `item.keys`, so a regression there shows up here first.
local leader = leader_popup()
local leader_headings = headings(leader)
t.ok(#leader_headings >= 3,
  ("<leader> groups are sectioned (%s)"):format(table.concat(leader_headings, ", ")))
t.ok(leader[1] and (leader[1].desc or ""):find("^── "),
  "the <leader> popup opens on a heading")

-- A prefix with nothing declared is left exactly as which-key ships it.
t.eq(#headings(popup("z")), 0, "z popup stays unheaded (nothing declared)")

t.done()
