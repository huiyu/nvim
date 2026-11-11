-- Popup sections: order, heading and colour for the keys under a prefix.
--
-- The layout itself is declared in lua/whichkey_spec.lua next to the mappings,
-- keyed by prefix/suffix with optional filetype/buftype filters and subgroup
-- labels. This file only reads it: nothing here knows what "files" or "search"
-- means, and context headings never register mappings or load a language plugin.
--
-- Matching is by mapping, not by description text. An earlier version matched
-- lowercased `desc` against Lua patterns, which meant a reworded description
-- silently changed a key's colour and position, and every new key needed a
-- pattern careful enough not to catch someone else's ("^search" swallowed ",F
-- Search and replace").
--
-- It also gives filetype plugins' own desc-less mappings (Python's ]], VimTeX's
-- ]n, man's gO) the descs declared there, so the popup shows words, not code.
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
---@return table<string, {order: number, section: table, label?: string}[]>
local function build_lookup()
  local by_keys = {}
  for prefix, list in pairs(Spec.sections or {}) do
    for order, section in ipairs(list) do
      for _, key in ipairs(section.keys or {}) do
        local lhs = norm(prefix .. key)
        by_keys[lhs] = by_keys[lhs] or {}
        table.insert(by_keys[lhs], { order = order, section = section, label = section.labels and section.labels[key] })
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
---@return {order: number, section: table, label?: string}?
local function entry_for(item)
  local keys = item.keys
  if not keys and item.keymap and item.keymap.lhs then
    -- `nvim_get_keymap` hands back a half-converted lhs: control keys are
    -- already the literal string "<C-A>" while a space is still a raw byte.
    -- keytrans alone would escape that "<" into "<lt>"; norm() round-trips
    -- through keycode first so both shapes land on which-key's form.
    keys = norm(item.keymap.lhs)
  end
  -- The popup does not take focus: current buffer is the source buffer.
  -- A key may belong to different sections in different filetypes (,v).
  for _, entry in ipairs(keys and LOOKUP[keys] or {}) do
    local section = entry.section
    if (not section.filetype or vim.tbl_contains(section.filetype, vim.bo.filetype))
      and (not section.buftype or section.buftype == vim.bo.buftype) then
      return entry
    end
  end
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
      if entry and entry.label and item.group then
        item.desc = entry.label
      end
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

--- Give a filetype plugin's own mappings in `buf` the descs from
--- `Spec.filetype_descs`.
---
--- The desc is written onto the buffer's mapping itself, never added as a
--- which-key entry: a which-key entry outlives a filetype change and outranks
--- the mapping that replaces it, while a mapping's own desc goes when
--- b:undo_ftplugin unmaps the key. mapset() re-creates the mapping from what
--- maparg() returned, with the same rhs or callback, script ID and flags, so
--- only the desc changes.
---
--- Only the buffer's own mappings, mode by mode: VimTeX maps nothing where a
--- global map already holds the key (illuminate's Normal ]], Nvim's Visual
--- ]n), and the global one keeps its own desc there.
---@param buf integer
local function describe_filetype_maps(buf)
  local descs = (Spec.filetype_descs or {})[vim.bo[buf].filetype]
  if not descs then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    for lhs, desc in pairs(descs) do
      for _, mode in ipairs({ "n", "x", "o" }) do
        local m = vim.fn.maparg(lhs, mode, false, true)
        if m.buffer == 1 and m.desc ~= desc then
          m.desc = desc
          vim.fn.mapset(m)
        end
      end
    end
  end)
end

--- Describe every loaded buffer now, and each one a filetype plugin maps later.
--- Registered at load, so this FileType handler runs after Nvim's own
--- `filetypeplugin` one, which sources the ftplugin (and VimTeX's) first.
local function install_filetype_descs()
  local filetypes = vim.tbl_keys(Spec.filetype_descs or {})
  if #filetypes == 0 then
    return
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("whichkey_filetype_descs", { clear = true }),
    pattern = filetypes,
    callback = function(args) describe_filetype_maps(args.buf) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      describe_filetype_maps(buf)
    end
  end
end

return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  dependencies = {
    "echasnovski/mini.icons",
  },
  opts = {
    -- Window preset. "classic" spans the full width along the bottom, which
    -- fills left-to-right but *sorts* top-to-bottom -- so a column reads a,b,
    -- the next d,g, and scanning across a row gives a,d,q,s,u,x: alphabetical
    -- everywhere except the direction the eye actually travels. "helix" caps
    -- the width instead, so the list is effectively one column and reads in
    -- order. Costs a corner of the editor while the popup is up.
    preset = "helix",
    -- Merged over the preset, which keeps the rest. Bottom-left, not helix's
    -- bottom-right: the AI panels own the right edge, so there the popup sat
    -- on the agent's input box, while the left edge is free but for the DAP
    -- panels. A hint glanced at mid-keystroke stays in one fixed corner
    -- rather than mid-screen, where it would cover the code being operated
    -- on and, with `no_overlap`, jump below the cursor whenever it met it.
    -- Up to 80 columns so descriptions are not cut, with room either side.
    win = {
      col = 0,
      width = { max = 80 },
      padding = { 0, 2 },
    },
    -- One column, always: which-key fits floor(width / (column + 3)) columns,
    -- and helix's 30-column minimum let two share an 80-column popup, so a
    -- short-rowed popup like <leader>'s split a heading from its items. A
    -- column of at least 40 leaves room for one.
    layout = { width = { min = 40 } },
    -- which-key's automatic triggers refuse every bare lowercase letter except
    -- `g` and `z` (`which-key/buf.lua`, `is_safe`): putting one on a letter
    -- makes that letter wait out 'timeoutlen' before its builtin can run. `s`
    -- is the window prefix here and has nothing bound to it on its own, so it
    -- had no popup at all while `<leader>`, `;` and `g` did.
    --
    -- Declaring it manually skips that check -- `is_safe` is called without
    -- `no_single` for manual triggers. The builtin this defers is `s`, which is
    -- `cl`: delete the character under the cursor and insert. `r` replaces a
    -- character without leaving Normal mode and `cw` changes a word, so the one
    -- it displaces is the one already spent on this prefix. Normal mode only --
    -- Visual `s` changes the selection and is worth keeping immediate.
    triggers = {
      { "<auto>", mode = "nxso" },
      { "s", mode = "n" },
    },
    -- Section first, then groups (+xxx) within a section.
    --
    -- The order of these two matters. With groups first, an undeclared group
    -- row jumps ahead of every section -- `<leader>m` put a bare "+Messages"
    -- above the "config" heading, which reads as a stray entry rather than the
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
    install_filetype_descs()
  end,
}
