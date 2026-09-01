local t = dofile("tests/helper.lua")

vim.cmd("Lazy! load diffview.nvim")
local keymaps = require("diffview.config").get_config().keymaps.file_panel
local stage
local blocked_semicolon
for _, map in ipairs(keymaps) do
  if map[1] == "n" and map[2] == "s" then stage = map end
  if map[1] == "n" and map[2] == ";" then blocked_semicolon = map end
end

t.ok(stage ~= nil, "Diffview file panel keeps an exact s mapping")
t.ok(stage and stage[4] and (stage[4].desc or ""):find("Stage / unstage", 1, true) ~= nil,
  "Diffview file-panel s still stages and unstages")
t.ok(blocked_semicolon and blocked_semicolon[4]
  and blocked_semicolon[4].desc == "Disabled in Diffview",
  "Diffview file panel still blocks the global file-picker prefix")

t.done()
