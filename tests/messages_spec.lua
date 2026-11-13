-- The cmdline and Vim's messages come from noice; vim.notify goes to the
-- snacks notifier, which noice hands Vim's messages to as well. Both need an
-- attached UI, which a headless spec never has, so this covers the headless
-- contract and the wiring. How they look and behave on screen is checked in a
-- real UI (AGENTS.md).
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")
local Plugin = require("lazy.core.plugin")

local noice = Config.plugins["noice.nvim"]
t.ok(noice ~= nil, "noice is part of the config")
t.ok(Config.plugins["nui.nvim"] ~= nil, "nui comes with it")

-- noice waits for VeryLazy, which lazy.nvim fires on the first UIEnter. A
-- headless run never fires that, so noice never attaches to the message grid
-- here: loaded, it would keep every warning and error off stderr, where the
-- startup check and these specs read them.
if noice then
  t.eq(Plugin.values(noice, "event", true), { "VeryLazy" }, "noice loads on VeryLazy")
  t.eq(noice._.loaded, nil, "headless: noice is not loaded")
end
t.eq(vim.g.did_very_lazy, nil, "headless: VeryLazy never fired")
-- ui2 and noice both take the message grid over; only noice may.
t.eq(package.loaded["vim._core.ui2"], nil, "ui2 is not enabled")

if noice then
  local opts = Plugin.values(noice, "opts", false)
  -- vim.notify stays the snacks notifier's, so every popup is the notifier's.
  t.eq(opts.notify.enabled, false, "noice leaves vim.notify to the snacks notifier")
  -- Each of these has an owner elsewhere, and two would draw the same thing:
  -- lualine's lsp_status, K's hover (tests/lsp_keymap_spec.lua) and blink's
  -- signature help (below).
  t.eq(opts.lsp.progress.enabled, false, "LSP progress is lualine's, not noice's")
  t.eq(opts.lsp.hover.enabled, false, "K's hover is Nvim's, not noice's")
  t.eq(opts.lsp.signature.enabled, false, "signature help is blink's, not noice's")
  -- noice's own handler is nil at the pinned commit (M._on_message), which
  -- would drop every window/showMessage a server sends.
  t.eq(opts.lsp.message.enabled, false, "a server's showMessage stays Nvim's handler, through vim.notify")

  -- Nvim 0.11+ message kinds noice's default routes do not list are dropped
  -- unless a route of ours takes them. These are the ones worth a view, and
  -- each leaves 20 lines and more to long_message_to_split's split. The other
  -- new kinds stay dropped: shell_cmd and search_cmd echo what was just typed,
  -- completion is Insert-mode completion's count (blink.cmp's menu shows it),
  -- and empty is a clear.
  local routed = {}
  for _, route in ipairs(opts.routes or {}) do
    local filter = route.filter or {}
    if filter.event == "msg_show" and route.view and not (route.opts or {}).skip then
      t.eq(filter.max_height, 19, "the route for " .. table.concat(filter.kind, ", ") .. " leaves 20+ lines to the split")
      for _, kind in ipairs(filter.kind) do routed[kind] = route.view end
    end
  end
  t.eq(routed, {
    shell_out = "notify", shell_err = "notify", shell_ret = "notify", verbose = "notify", wildlist = "notify",
    progress = "mini", undo = "mini", quickfix = "mini",
  }, ":! output pops up like other messages; :w, u and quickfix confirmations are small at the bottom right")

  -- :w's first `progress` message is the bare path, which Nvim replaces by id
  -- and noice would show as a second line.
  local skip
  for _, route in ipairs(opts.routes or {}) do
    if (route.opts or {}).skip and (route.filter or {}).kind == "progress" then skip = route.filter.find end
  end
  t.ok(skip and ('"/tmp/a b.txt" '):find(skip) ~= nil, ":w's bare-path progress message is skipped")
  t.ok(skip and not ('"/tmp/a b.txt" [New] 2L, 4B written'):find(skip), "and its 'written' line is not")
end

-- noice skips msg_showcmd, so 'showcmd' lives in the statusline instead.
t.eq(vim.o.showcmd, true, "'showcmd' is on")
t.eq(vim.o.showcmdloc, "statusline", "and shown in the statusline, which noice leaves alone")
require("lazy").load({ plugins = { "lualine.nvim" } })
t.ok(vim.tbl_contains(require("lualine").get_config().sections.lualine_x, "%S"),
  "lualine draws it (%S)")

-- The notifier would take vim.notify over and keep it off stderr, which is
-- where the startup check looks for warnings and errors.
t.eq(Snacks.config.notifier.enabled, false, "headless: the snacks notifier stays off")
t.ok(debug.getinfo(vim.notify, "S").source:find("vim/_core/editor", 1, true) ~= nil,
  "headless: vim.notify is still Nvim's own")

-- A UI that attaches after startup (--headless --listen, then --remote-ui)
-- gets the notifier on its first UIEnter, the event lazy.nvim also uses to
-- run VeryLazy late (and so to load noice). A headless run never fires it, so
-- the hook is called directly here to check what it would do.
local notify_hook
for _, au in ipairs(vim.api.nvim_get_autocmds({ event = "UIEnter" })) do
  if au.desc == "Route vim.notify to the snacks notifier for a UI that attached after startup" then
    notify_hook = au
  end
end
t.ok(notify_hook and notify_hook.once, "headless: the notifier waits for the first UIEnter")
if notify_hook then
  local builtin_notify = vim.notify
  notify_hook.callback()
  t.eq(vim.notify, Snacks.notifier.notify, "the notifier hook routes vim.notify to snacks")
  -- noice's notify view uses the notifier only when its flag reads enabled,
  -- and falls back to a view of its own otherwise.
  t.eq(Snacks.config.notifier.enabled, true, "the notifier hook also marks the notifier enabled")
  vim.notify = builtin_notify
  Snacks.config.notifier.enabled = false
end

-- <leader>mn holds both histories. :messages and g< are Vim's own, which noice
-- shows in a split (q closes).
for lhs, desc in pairs({
  ["<leader>mnh"] = "Notification history",
  ["<leader>mnt"] = "Search notifications",
  ["<leader>mnl"] = "Last command output",
  ["<leader>mna"] = "Message history",
  ["<leader>un"] = "Dismiss notifications",
}) do
  t.eq(vim.fn.maparg(lhs, "n", false, true).desc, desc, lhs .. " is " .. desc)
end
t.eq(vim.fn.maparg("<leader>mnl", "n"), "g<", "<leader>mnl is Vim's g<")
t.eq(vim.fn.maparg("<leader>mna", "n"), "<Cmd>messages<CR>", "<leader>mna is Vim's :messages")
-- One act, one key: <leader>un dismisses, and <leader>mn holds the histories.
t.eq(vim.fn.maparg("<leader>mnd", "n"), "", "<leader>mnd is gone; <leader>un dismisses")
local group
for _, entry in ipairs(require("config.whichkey_spec").spec) do
  if entry[1] == "<leader>mn" then group = entry.group end
end
-- Both histories live here: Vim's messages and the notifier's notifications.
t.eq(group, "Messages/notifications", "<leader>mn names both histories, not Noice")

-- Automatic signature help is blink's.
require("lazy").load({ plugins = { "blink.cmp" } })
t.eq(require("blink.cmp.config").signature.enabled, true, "blink shows signature help while typing")

t.done()
