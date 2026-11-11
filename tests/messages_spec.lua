-- Messages, notifications and the cmdline come from Nvim's ui2 and the snacks
-- notifier; noice is gone. Both need an attached UI, which a headless spec
-- never has, so this covers the headless contract and the wiring. How they
-- look and behave on screen is checked in a real UI (AGENTS.md).
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")

t.eq(Config.plugins["noice.nvim"], nil, "noice is not part of the config")
t.eq(Config.plugins["nui.nvim"], nil, "nui went with it: nothing else required it")

-- options.lua asks for ui2, and enable() returns before opening anything when
-- no UI is attached, so --headless keeps writing messages to stdout/stderr.
local ui2 = package.loaded["vim._core.ui2"]
t.ok(ui2 ~= nil, "options.lua loads ui2")
if ui2 then
  for _, name in ipairs({ "cmd", "msg", "pager", "dialog" }) do
    t.eq(ui2.wins[name], -1, "headless: ui2 opens no " .. name .. " window")
  end
end

-- The notifier would take vim.notify over and keep it off stderr, which is
-- where the startup check looks for warnings and errors.
t.eq(Snacks.config.notifier.enabled, false, "headless: the snacks notifier stays off")
t.ok(debug.getinfo(vim.notify, "S").source:find("vim/_core/editor", 1, true) ~= nil,
  "headless: vim.notify is still Nvim's own")

-- A UI that attaches after startup (--headless --listen, then --remote-ui)
-- gets both on its first UIEnter, the event lazy.nvim also uses to run
-- VeryLazy late. A headless run never fires it, so the hooks are called
-- directly here to check what they would do.
local deferred = {}
for _, au in ipairs(vim.api.nvim_get_autocmds({ event = "UIEnter" })) do
  if au.desc then deferred[au.desc] = au end
end
local ui2_hook = deferred["Enable ui2 for a UI that attached after startup"]
local notify_hook = deferred["Route vim.notify to the snacks notifier for a UI that attached after startup"]
t.ok(ui2_hook and ui2_hook.once, "headless: ui2 waits for the first UIEnter")
t.ok(notify_hook and notify_hook.once, "headless: the notifier waits for the first UIEnter")
if ui2_hook and ui2 then
  ui2_hook.callback()
  t.eq(ui2.wins.cmd, -1, "the ui2 hook still opens nothing while no UI is attached")
end
if notify_hook then
  local builtin_notify = vim.notify
  notify_hook.callback()
  t.eq(vim.notify, Snacks.notifier.notify, "the notifier hook routes vim.notify to snacks")
  vim.notify = builtin_notify
end

-- <leader>mn* replaced noice's history keys with the notifier and ui2's pager.
for lhs, desc in pairs({
  ["<leader>mnh"] = "Notification history",
  ["<leader>mnt"] = "Search notifications",
  ["<leader>mnd"] = "Dismiss notifications",
  ["<leader>mnl"] = "Last command output",
  ["<leader>mna"] = "Message history",
  ["<leader>un"] = "Dismiss notifications",
}) do
  t.eq(vim.fn.maparg(lhs, "n", false, true).desc, desc, lhs .. " is " .. desc)
end
t.eq(vim.fn.maparg("<leader>mnl", "n"), "g<", "<leader>mnl is ui2's g< pager")
local group
for _, entry in ipairs(require("whichkey_spec").spec) do
  if entry[1] == "<leader>mn" then group = entry.group end
end
-- Both histories live here: ui2's messages and the notifier's notifications.
t.eq(group, "Messages/notifications", "<leader>mn names both histories, not Noice")

-- Automatic signature help moved from noice to blink.
require("lazy").load({ plugins = { "blink.cmp" } })
t.eq(require("blink.cmp.config").signature.enabled, true, "blink shows signature help while typing")

t.done()
