local t = dofile("tests/helper.lua")

local function mapping(lhs, mode)
  return vim.fn.maparg(lhs, mode, false, true)
end

for _, lhs in ipairs({ "<C-]>", "<C-\\>" }) do
  local insert = mapping(lhs, "i")
  t.eq(insert.rhs, "<Esc>", lhs .. " leaves Editor input through Escape")
  t.eq(insert.desc, "Exit input mode", lhs .. " Insert mapping is discoverable")

  local terminal = mapping(lhs, "t")
  t.eq(terminal.rhs, "<C-\\><C-n>", lhs .. " reaches terminal-Normal mode")
  t.eq(terminal.desc, "Exit input mode", lhs .. " terminal mapping is discoverable")

  -- Visual too: a selection made with an input method still active needs the
  -- same exit, and leaving it to the global Normal-mode map would clear the
  -- highlight instead of dropping the selection.
  local visual = mapping(lhs, "x")
  t.eq(visual.rhs, "<Esc>", lhs .. " leaves a Visual selection")
  t.eq(visual.desc, "Exit selection mode", lhs .. " Visual mapping is discoverable")
end

for _, lhs in ipairs({ "<C-]>", "<C-\\>" }) do
  local normal = mapping(lhs, "n")
  t.ok(normal.rhs:find("nohlsearch", 1, true) ~= nil,
    "repeated Normal-mode " .. lhs .. " stays a harmless Escape")
end

-- `help` and `man` navigate with <C-]>, so the global Escape steps aside there.
-- maparg reports the mapping of the *current* buffer, so the scratch buffer has
-- to be entered rather than just created.
local origin = vim.api.nvim_get_current_buf()
for _, ft in ipairs({ "help", "man" }) do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = ft

  local restored = mapping("<C-]>", "n")
  t.eq(restored.buffer, 1, ft .. " restores <C-]> buffer-locally")
  t.eq(restored.rhs, "<C-]>", ft .. " follows the tag under the cursor")
  t.eq(restored.noremap, 1, ft .. " reaches the builtin, not the global Escape")
  -- The Escape half is not lost with the tag jump.
  t.ok(mapping("<C-\\>", "n").rhs:find("nohlsearch", 1, true) ~= nil,
    ft .. " keeps <C-\\> as the Escape that clears hlsearch")

  vim.api.nvim_set_current_buf(origin)
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- An ordinary buffer is unaffected: the global Escape is still what answers.
t.eq(mapping("<C-]>", "n").buffer, 0,
  "an ordinary buffer keeps the global repeatable Escape")

local comma_normal = mapping("<C-,>", "n")
t.ok(comma_normal.rhs:find("WindowFocusEditor", 1, true) ~= nil,
  "Normal-mode Ctrl-comma toggles the editor window")
local comma_terminal = mapping("<C-,>", "t")
t.ok(comma_terminal.rhs:find("<C-\\><C-n>", 1, true) ~= nil,
  "terminal Ctrl-comma first leaves terminal input")
t.ok(comma_terminal.rhs:find("WindowFocusEditor", 1, true) ~= nil,
  "terminal Ctrl-comma reaches the editor in one press")

-- Ctrl-comma needs the extended-key protocol. se is the plain-key twin
-- for the terminals that never negotiate it, so the editor jump stays reachable
-- where the chord cannot be sent at all.
--
-- Asserted against the spec table, not maparg: which-key runs `add()` on its
-- own trie and never calls vim.keymap.set, so a spec-registered key is not
-- visible to
-- maparg (`se` included). Loading the plugin first is still worth it -- `add()` runs in the
-- plugin's config, so a malformed entry raises here rather than in a session.
vim.cmd("Lazy! load which-key.nvim")
t.ok(package.loaded["which-key"] ~= nil, "which-key accepted the spec")

local leader_editor
for _, entry in ipairs(require("whichkey_spec")) do
  if entry[1] == "se" then leader_editor = entry end
end
t.ok(leader_editor ~= nil, "se is the plain-key fallback for the editor jump")
t.ok(leader_editor and type(leader_editor[2]) == "string"
  and leader_editor[2]:find("WindowFocusEditor", 1, true) ~= nil,
  "se runs the same command as Ctrl-comma")
t.ok(leader_editor and (leader_editor.desc or ""):find("Editor window", 1, true) ~= nil,
  "se is discoverable in the Window group")

t.done()
