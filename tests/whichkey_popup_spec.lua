local t = dofile("tests/helper.lua")

-- Two things are under test here.
--
-- The section layout is declared in lua/config/whichkey_spec.lua and read by
-- lua/plugins/editor/whichkey.lua. A suffix listed there that maps to nothing is
-- dead weight nobody would notice, so the global file-search declarations are
-- resolved against real mappings. context_actions_spec.lua covers filetype menus.
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

local Spec = require("config.whichkey_spec")

-- Description-only spec entries live in which-key's trie. Entries with an RHS
-- become real mappings after scheduled setup; that has not run yet here.
-- Buffer-local LSP and filetype actions are exercised by their integration specs.
local spec_lhs = {}
for _, entry in ipairs(Spec.spec) do
  if type(entry[1]) == "string" then
    spec_lhs[vim.keycode(entry[1])] = true
  end
end
-- "mode lhs" -> desc of every description-only entry. Read now: which-key's
-- setup rewrites the spec tables in place when it parses them.
local desc_only = {}
for _, entry in ipairs(Spec.spec) do
  if type(entry[1]) == "string" and entry[2] == nil and entry.desc then
    for _, m in ipairs(type(entry.mode) == "table" and entry.mode or { entry.mode or "n" }) do
      desc_only[m .. " " .. entry[1]] = entry.desc
    end
  end
end
-- lhs -> group label, read before setup for the same reason.
local group_of = {}
for _, entry in ipairs(Spec.spec) do
  if type(entry[1]) == "string" and entry.group then group_of[entry[1]] = entry.group end
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
  -- which-key's node form: keytrans, with its "<lt>" stored as a bare "<".
  local function wk_keys(lhs) return (vim.fn.keytrans(vim.keycode(lhs)):gsub("<lt>", "<")) end
  local pn = wk_keys(prefix)
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    -- keycode first: a raw lhs mixes literal "<C-A>" with real bytes.
    local keys = wk_keys(m.lhs)
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
expected[#expected + 1] = Spec.fallback_section[1]
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

-- Keys land under their declared heading, matched by key.
local function owner_of(prefix, key)
  local owner
  for _, row in ipairs(popup(prefix)) do
    if row.key == "" then owner = row.desc:gsub("^── ", "")
    elseif row.key == key then return owner end
  end
end
-- A few representatives: each case restates one entry of
-- lua/config/whichkey_spec.lua, so the rest add nothing the lookup proves.
for _, case in ipairs({
  { ";", "c", "positions" },
  -- The keys that spend API credits: inline edits and the profile they bill.
  { "<leader>a", "e", "HTTP · API credits" }, { "<leader>a", "x", "HTTP · API credits" },
  -- Case is the debug variant of the same run: tM sits with tm.
  { "<leader>t", "M", "run" },
  { "]", "r", "code" }, { "[", "r", "code" },
}) do
  t.eq(owner_of(case[1], case[2]), case[3], ("%s%s sits under %s"):format(case[1], case[2], case[3]))
end
-- The keys that spend API credits say so in their heading; the chats' billing
-- is in the new-chat picker's entries. <leader>ap, once the +CodeCompanion
-- group and then the action palette, is gone.
local ai_headings = headings(popup("<leader>a"))
t.ok(#ai_headings >= 6, ("<leader>a popup is sectioned (%s)"):format(table.concat(ai_headings, ", ")))
t.ok(vim.tbl_contains(ai_headings, "HTTP · API credits") and not vim.tbl_contains(ai_headings, "ACP chat · subscription"),
  "the API-credit keys have a billing heading, and no per-kind chat heading is left")
t.ok(not vim.tbl_contains(ai_headings, "others"), "every <leader>a key is declared in a section")
t.ok(not vim.iter(Spec.spec):any(function(entry) return entry[1] == "<leader>ap" end),
  "<leader>ap is not declared")
-- gs is buffer-local to vtsls buffers, so only the declaration can be checked here.
local g_lsp = vim.iter(Spec.sections["g"]):find(function(section) return section[1] == "LSP" end)
t.ok(g_lsp and vim.tbl_contains(g_lsp.keys, "s"), "gs is declared in the g LSP section")
-- Sections with a filetype must come before the unfiltered ones that declare
-- the same key, or the first match (LSP, lines) takes it in that view too.
for _, prefix in ipairs({ "g", "," }) do
  local unfiltered = {}
  for _, section in ipairs(Spec.sections[prefix]) do
    for _, key in ipairs(section.keys) do
      if section.filetype and unfiltered[key] then
        t.ok(false, ("%s%s in %q is shadowed by %q above it"):format(prefix, key, section[1], unfiltered[key]))
      end
    end
    if not section.filetype and not section.buftype then
      for _, key in ipairs(section.keys) do unfiltered[key] = unfiltered[key] or section[1] end
    end
  end
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

-- Unclassified keys must never look like members of the preceding section.
local function item(keys, group)
  return { keys = keys, key = keys:sub(-1), raw_key = keys, desc = keys, group = group }
end
local mixed = { item("ge"), item("gS"), item("g'"), item("gz", true), item("gf") }
View.sort(mixed)
t.eq(headings(mixed), { "edit", "marks", "others" }, "unclassified keys get one trailing others heading")
local owner, owners, others_keys = nil, {}, {}
for _, row in ipairs(mixed) do
  if row.key == "" then owner = row.desc:sub(#"── " + 1)
  else
    owners[row.keys] = owner
    if owner == "others" then others_keys[#others_keys + 1] = row.keys end
  end
end
t.eq(owners, { gS = "edit", ["g'"] = "marks", ge = "others", gf = "others", gz = "others" },
  "every item, including unknown group rows, belongs to the correct section")
t.eq(others_keys, { "gz", "ge", "gf" }, "unknown groups and keys retain their order inside others")

local single_tail = { item("gO"), item("gf") }
View.sort(single_tail)
t.eq(headings(single_tail), { "LSP", "others" }, "one declared section and one leftover still have separate headings")
t.eq(single_tail[3].keymap, nil, "others heading is display-only")
t.eq(single_tail[3].key, "", "others heading introduces no shortcut")
local no_tail = { item("gO"), item("gS") }
View.sort(no_tail)
t.eq(headings(no_tail), { "LSP", "edit" }, "fully classified popups have no empty others section")

-- Use which-key's real trie so the screenshot's builtins (ge/gf/gg/...) and
-- description-only group rows participate, not just nvim_get_keymap entries.
local Config = require("which-key.config")
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
t.ok(vim.wait(1000, function() return Config.loaded end), "which-key finishes its scheduled setup")
local mode = require("which-key.buf").get({ mode = "n", update = true })
local node = mode.tree:find("g")
local real = {}
for _, child in ipairs(node:children()) do real[#real + 1] = View.item(child, { parent = node }) end
View.sort(real)
local real_headings = headings(real)
t.eq(real_headings[#real_headings], "others", "real g popup ends with the others section")
owner, owners = nil, {}
for _, row in ipairs(real) do
  if row.key == "" then owner = row.desc:sub(#"── " + 1)
  else owners[row.keys] = owner end
end
t.eq({ owners.ge, owners.gf, owners.gg, owners.gx }, { "others", "others", "others", "others" },
  "real g builtins and gx do not fall under marks")

vim.o.lines, vim.o.columns = 100, 120
local State = require("which-key.state")
State.state = { mode = mode, node = node, filter = {}, show = true, started = vim.uv.hrtime() }
View.show()
local rendered = table.concat(vim.api.nvim_buf_get_lines(View.view.buf, 0, -1, false), "\n")
local others_at = rendered:find("── others", 1, true)
local file_at = rendered:find("Go to file under cursor", 1, true)
t.ok(others_at and file_at and others_at < file_at, "rendered g popup puts others before the unclassified builtins")
-- Bottom-left: the AI panels own the right edge, where helix would put it.
local win = View.view and View.view.win
local pos = win and vim.api.nvim_win_get_position(win)
local width = win and vim.api.nvim_win_get_width(win)
t.eq(pos and pos[2], 0, "the popup sits at the left edge")
t.ok(pos and pos[1] + vim.api.nvim_win_get_height(win) + 2 >= vim.o.lines - vim.o.cmdheight - 1,
  "along the bottom (row " .. tostring(pos and pos[1]) .. ")")
t.ok(width and width <= 80, ("no wider than 80 columns (%s)"):format(tostring(width)))
t.eq({ Config.options.win.width.max, Config.options.win.width.min, Config.options.win.padding },
  { 80, 30, { 0, 2 } }, "which may grow to 80 columns (helix stops at 60), keeping helix's minimum, with padding")
State.stop()

-- Still one column where rows are short: which-key fits as many columns as
-- the width allows, and <leader>'s rows once let two share 80 columns.
local leader = mode.tree:find(vim.g.mapleader == " " and "<Space>" or vim.g.mapleader)
t.ok(leader ~= nil, "the <leader> node exists")
State.state = { mode = mode, node = leader, filter = {}, show = true, started = vim.uv.hrtime() }
View.show()
local widest = 0
for _, l in ipairs(vim.api.nvim_buf_get_lines(View.view.buf, 0, -1, false)) do
  local _, rows = l:gsub("➜", "")
  widest = math.max(widest, rows)
end
t.eq(widest, 1, "the <leader> popup lays its rows out in one column")
State.stop()

-- which-key's automatic triggers skip every bare lowercase letter but `g` and
-- `z` (`which-key/buf.lua`, `is_safe`), so the window prefix had no popup while
-- every other prefix did. Asserted against the resolved config rather than
-- `maparg`: triggers attach per buffer, so whether one is installed right now
-- depends on state this spec has just stopped.
local triggers = require("which-key.config").triggers
local declared = {}
for _, mapping in ipairs(triggers.mappings or {}) do
  declared[mapping.lhs .. ":" .. mapping.mode] = true
end
t.ok(declared["s:n"], "the window prefix is declared as a trigger, so `s` opens a popup")
t.ok(not declared["s:x"], "Visual s is left alone, where it changes the selection")
t.ok(triggers.modes and triggers.modes.n, "automatic triggers are still on for every other prefix")

---------------------------------------------------------------------------
-- Desc-only entries never stand over a key a buffer remaps
---------------------------------------------------------------------------

-- which-key reads a spec entry's desc before the mapping's own, buffer-local
-- ones included: a global "Next class start" row named CodeDiff's ]c "Next
-- hunk", and "[LSP] Document symbols" markdown's outline. Keys with such
-- twins carry real descs on the global mapping instead.
for _, key in ipairs({ "n ]c", "n [c", "n ]C", "n [C", "n ]m", "n [m", "n ]M", "n [M", "o ]m",
  "x ac", "o ic", "o af", "x if", "n gO" }) do
  t.eq(desc_only[key], nil, key .. " has no desc-only entry to outrank a buffer's own")
end
require("lazy").load({ plugins = { "nvim-treesitter-textobjects" } })
for lhs, want in pairs({
  ["]c"] = "Next class start (diff: next hunk)", ["[c"] = "Prev class start (diff: prev hunk)",
  ["]C"] = "Next class end", ["[M"] = "Prev function end", ["]m"] = "Next function start",
}) do
  t.eq(vim.fn.maparg(lhs, "o", false, true).desc, want, lhs .. " carries its own desc")
end
t.eq({ vim.fn.maparg("ac", "x", false, true).desc, vim.fn.maparg("if", "o", false, true).desc },
  { "class", "inner function" }, "the treesitter text objects use the popup's words")
for _, case in ipairs({ { "]", "m" }, { "[", "M" }, { "]", "c" }, { "[", "C" } }) do
  t.eq(owner_of(case[1], case[2]), "code", case[1] .. case[2] .. " sits under code, not others")
end

-- A view's own ]c (CodeDiff's, gitsigns' diff panel) is what the popup shows.
local diff_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(diff_buf)
vim.keymap.set("n", "]c", "<Nop>", { buffer = diff_buf, desc = "Next hunk" })
local diff_mode = require("which-key.buf").get({ mode = "n", update = true })
local bracket = diff_mode.tree:find("]")
local hunk = diff_mode.tree:find("]c")
t.eq(hunk and View.item(hunk, { parent = bracket }).desc, "Next hunk", "a buffer-local ]c keeps its own desc")
vim.api.nvim_buf_delete(diff_buf, { force = true })

-- Nvim's LSP defaults keep their callbacks; only the code-as-desc is gone.
for _, case in ipairs({
  { "n", "gO", "[LSP] Document symbols (Nvim default)" },
  { "n", "grr", "[LSP] References" }, { "n", "gri", "[LSP] Implementation" },
  -- grn and gra ask first (the new name, which action), worded as ,r and ,a.
  { "n", "grt", "[LSP] Type definition" }, { "n", "grn", "[LSP] Rename…" },
  { "n", "gra", "[LSP] Code action…" }, { "x", "gra", "[LSP] Code action…" },
  { "n", "grx", "[LSP] Run codelens" },
}) do
  local m = vim.fn.maparg(case[2], case[1], false, true)
  t.eq({ m.desc, m.buffer, type(m.callback) }, { case[3], 0, "function" },
    ("%s %s is Nvim's own mapping, described"):format(case[1], case[2]))
end

-- mini.bracketed maps its jump motions in Operator-pending mode too, where
-- its own "Jump forward" showed beside every other "Next X" row.
t.eq({ desc_only["o ]j"], desc_only["o [J"] }, { "Next jump", "First jump" },
  "the jumplist rows are worded alike after an operator")
t.eq(desc_only["x ]j"], nil, "and not advertised in Visual, where mini.bracketed maps no jump")

-- The , menu is about the current file or view; "buffer" names the buffer list.
t.eq(group_of[","], "File/view actions", ", is labelled by its scope")

-- Labels in the g and text-object popups follow those popups' house style:
-- sentence case under g, which-key's lowercase nouns after an operator.
for _, key in ipairs({ "n '", "n `", "n g'", "n g`", "n g[", "n g]" }) do
  t.ok((desc_only[key] or ""):match("^%u"), key .. " is in sentence case: " .. tostring(desc_only[key]))
end
for key, want in pairs({
  ["o al"] = "last textobject (al + object key)", ["x il"] = "inner last textobject (il + object key)",
  ["o an"] = "parent node", ["x in"] = "child node",
  ["x ]n"] = "Next node", ["x [N"] = "Prev sibling (extend)",
}) do
  t.eq(desc_only[key], want, key .. " is worded like its popup")
end
t.eq(desc_only["o ]n"], nil, "VimTeX's Operator-pending ]n (math zone) is not labelled as a node")

t.done()
