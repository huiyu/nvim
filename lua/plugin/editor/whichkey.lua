-- Popup sections: order, heading and colour for the keys under a prefix.
--
-- The layout itself is declared in lua/whichkey_spec.lua next to the mappings,
-- keyed by prefix and suffix. This file only reads it: nothing here knows what
-- "files" or "search" means, so adding a key or a whole section is a data edit
-- in one place, never a code change here.
--
-- Matching is by mapping, not by description text. An earlier version matched
-- lowercased `desc` against Lua patterns, which meant a reworded description
-- silently changed a key's colour and position, and every new key needed a
-- pattern careful enough not to catch someone else's ("^search" swallowed ",F
-- Search and replace").
local Spec = require("whichkey_spec")

--- Normalise a key sequence to the form which-key stores on a node.
---
--- which-key runs every key through `keytrans(replace_termcodes(...))`
--- (`util.lua`, `M.norm`), which turns a literal space into "<Space>" and
--- "<c-q>" into "<C-Q>". Declarations can therefore be written naturally --
--- "<space>", "<C-q>" -- and still match.
---@param keys string
---@return string
local function norm(keys)
  return vim.fn.keytrans(vim.keycode(keys))
end

--- Lookup from full key sequence to its declared section.
---@return table<string, {order: number, section: table}>
local function build_lookup()
  local by_keys = {}
  for prefix, list in pairs(Spec.sections or {}) do
    for order, section in ipairs(list) do
      for _, key in ipairs(section.keys or {}) do
        by_keys[norm(prefix .. key)] = { order = order, section = section }
      end
    end
  end
  return by_keys
end

local LOOKUP = build_lookup()

--- The declared entry for an item, or nil when the key is in no section.
---
--- `item.keys` is the node's full key sequence, already normalised, and exists
--- for group rows too -- which is what lets a `<leader>` popup of nothing but
--- groups be sectioned. The keymap fallback covers any row that carries a real
--- mapping without a node behind it.
---@param item table which-key item (keys, key, desc, keymap, group)
---@return {order: number, section: table}?
local function entry_for(item)
  local keys = item.keys
  if not keys and item.keymap and item.keymap.lhs then
    -- `nvim_get_keymap` hands back a half-converted lhs: control keys are
    -- already the literal string "<C-A>" while a space is still a raw byte.
    -- keytrans alone would escape that "<" into "<lt>"; norm() round-trips
    -- through keycode first so both shapes land on which-key's form.
    keys = norm(item.keymap.lhs)
  end
  return keys and LOOKUP[keys] or nil
end

--- Sort key: the section's position, or 99 for an undeclared key.
---
--- Undeclared keys keep their alphabetical order among themselves and sit after
--- every section, so a new mapping shows up in a sensible place before anyone
--- decides which section it belongs to.
---
--- This runs through which-key's own `sort` option, so the grouping survives
--- even if the heading patch below ever stops applying.
---@param item table
---@return number
local function section_order(item)
  local entry = entry_for(item)
  return entry and entry.order or 99
end

--- Minimum number of visible sections, including the fallback section.
--- A popup with no declared entries keeps which-key's default layout.
local MIN_SECTIONS = 2

--- Insert heading rows between sections, and paint each key its section colour.
---
--- which-key has no separator of its own: the popup body is a table whose rows
--- *are* the items (view.lua builds `Layout.new({ cols = cols, rows = items })`),
--- and its render loop reads only `key`, `sep`, `icon`, `desc`, `group` and
--- `icon_hl` off each row. A row carrying nothing but a heading is therefore
--- safe -- it is display data, and never reaches key handling, which walks the
--- trie rather than this list.
---
--- This is the one place here that reaches into which-key's internals. It
--- replaces `View.sort`, which the popup calls as `M.sort(items)` on its own
--- module table, so overwriting the field is enough to be picked up. If a later
--- version renames it or stops routing through the module table, the guards
--- below leave the popup exactly as which-key ships it -- headings and colours
--- are dropped, ordering still works, nothing errors.
---
--- Note this assumes the single-column "helix" preset. A multi-column preset
--- slices the item list into equal-height boxes, so a heading can land at the
--- bottom of one column with its items at the top of the next.
local function install_section_headings()
  local ok, View = pcall(require, "which-key.view")
  if not ok or type(View.sort) ~= "function" then
    return
  end

  local base_sort = View.sort

  View.sort = function(items, fields)
    base_sort(items, fields)

    local seen, count, has_others = {}, 0, false
    for _, item in ipairs(items) do
      local entry = entry_for(item)
      if entry and not seen[entry.section] then
        seen[entry.section] = true
        count = count + 1
      elseif not entry then
        has_others = true
      end
    end
    if count == 0 then return end
    if has_others then count = count + 1 end
    if count < MIN_SECTIONS then
      return
    end

    local result, previous = {}, nil
    for _, item in ipairs(items) do
      local entry = entry_for(item)
      local section = entry and entry.section or Spec.fallback_section
      -- Paint the key itself, so the heading and its rows read as one block.
      item.icon = section.icon or item.icon
      item.icon_hl = "WhichKeyIcon"
        .. section.color:sub(1, 1):upper() .. section.color:sub(2)
      if section ~= previous then
        result[#result + 1] = {
          key = "",
          raw_key = "",  -- View.sort's final tie-break compares this
          sep = " ",     -- suppress the arrow the separator column defaults to
          icon = section.icon,
          icon_hl = item.icon_hl,
          desc = "── " .. section[1],
          group = true,  -- render loop picks WhichKeyGroup for a group's desc
        }
      end
      previous = section
      result[#result + 1] = item
    end

    -- Rewrite in place: the caller passes `items` and ignores any return value.
    for i = #items, 1, -1 do
      items[i] = nil
    end
    for i, item in ipairs(result) do
      items[i] = item
    end
  end
end

return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  dependencies = {
    "echasnovski/mini.nvim",
    "echasnovski/mini.icons",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    -- Window preset. "classic" spans the full width along the bottom, which
    -- fills left-to-right but *sorts* top-to-bottom -- so a column reads a,b,
    -- the next d,g, and scanning across a row gives a,d,q,s,u,x: alphabetical
    -- everywhere except the direction the eye actually travels. "helix" caps
    -- the width instead, so the list is effectively one column and reads in
    -- order. Costs a corner of the editor while the popup is up.
    --
    -- The presets *plugin* below is unrelated: it documents built-in keys and
    -- creates no mappings of its own.
    preset = "helix",
    presets = {
      operators = true,    -- adds help for operators like d, y, ... and registers them for motion / text object completion
      motions = true,      -- adds help for motions
      text_objects = true, -- help for text objects triggered after entering an operator
      windows = true,      -- default bindings on <c-w>
      nav = true,          -- misc bindings to work with windows
      z = true,            -- bindings for folds, spelling and others prefixed with z
      g = true,            -- bindings for prefixed with g
    },
    -- Section first, then groups (+xxx) within a section.
    --
    -- The order of these two matters. With groups first, an undeclared group
    -- row jumps ahead of every section -- `<leader>m` put a bare "+Noice" above
    -- the "config" heading, which reads as a stray entry rather than the
    -- uncategorised tail it is. Sectioning first keeps every heading and its
    -- rows together and leaves undeclared keys, groups included, at the end.
    --
    -- which-key's built-in `group` sorter returns 1 for groups → groups come
    -- last under default a<b sort, so we invert it here.
    sort = {
      section_order,                                    -- declared sections
      function(item) return item.group and 0 or 1 end, -- groups first within one
      "alphanum",                                       -- alphanum before symbols
      "case",                                           -- lowercase before uppercase
      "natural",                                        -- natural order of remaining
    },
  },
  config = function(_, opts)
    local whichkey = require("which-key")
    whichkey.setup(opts)
    install_section_headings()
    -- Spec data lives in lua/whichkey_spec.lua; the imperative keymaps are in
    -- lua/mappings.lua (required for side effects by init.lua).
    whichkey.add(Spec.spec)
  end,
}
