local t = dofile("tests/helper.lua")
local dap = require("dap")
local ui = require("util.dap")
local watches = require("dapui").elements.watches

-- Invoke real mappings in live Visual modes, not stale '< and '> marks.
local original_hover = require("dap.ui.widgets").hover
local evaluated
require("dap.ui.widgets").hover = function(expr) evaluated = expr end
vim.cmd.enew()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha + beta", "gamma + delta" })
vim.fn.setreg("z", "untouched")
for _, case in ipairs({
  { "gg0v4l", "alpha" },
  { "gg04lv4h", "alpha" },
  { "ggVj", "alpha + beta\ngamma + delta" },
  { "gg0<C-v>j4l", "alpha\ngamma" },
}) do
  evaluated = nil
  vim.api.nvim_feedkeys(vim.keycode(case[1] .. "<Space>dw"), "xt", false)
  t.eq(evaluated, case[2], "evaluate selection: " .. case[1])
  t.eq(vim.fn.mode(), "n", "evaluation leaves Visual mode")
end
t.eq(vim.fn.getreg("z"), "untouched", "evaluation preserves registers")
require("dap.ui.widgets").hover = original_hover

local input = vim.ui.input
vim.ui.input = function(opts, cb)
  t.eq(opts.default, "alpha + beta", "watch starts from the selected expression")
  cb("alpha + beta")
end
vim.api.nvim_feedkeys(vim.keycode("gg0v$h<Space>dW"), "xt", false)
t.eq(watches.get()[1].expression, "alpha + beta", "watch stores the full expression")
vim.ui.input = function(_, cb) cb(nil) end
ui.watch()
t.eq(#watches.get(), 1, "cancelled watch adds nothing")
vim.ui.input = input

local fn_input = vim.fn.input
vim.fn.input = function() return "value={alpha}" end
ui.logpoint()
local bufnr = vim.api.nvim_get_current_buf()
local points = require("dap.breakpoints").get(bufnr)[bufnr]
t.eq(points[1].logMessage, "value={alpha}", "logpoint stores message without a condition")
t.eq(points[1].condition, nil, "logpoint is not a conditional breakpoint")
vim.fn.input = function() return "" end
ui.logpoint()
t.eq(require("dap.breakpoints").get(bufnr)[bufnr], points, "empty logpoint preserves existing breakpoint")
vim.fn.input = fn_input

local select, session, set = vim.ui.select, dap.session, dap.set_exception_breakpoints
local target = { capabilities = { exceptionBreakpointFilters = {
  { filter = "raised", label = "Raised Exceptions" }, { filter = "uncaught", label = "Uncaught Exceptions" },
} } }
dap.session = function() return target end
local filters, delayed
dap.set_exception_breakpoints = function(value) filters = value end
vim.ui.select = function(choices, _, cb)
  t.eq(choices[3].label, "Raised Exceptions", "exception names come from the adapter")
  cb(choices[2])
  delayed = function() cb(choices[1]) end
end
ui.exceptions()
t.eq(filters, { "raised", "uncaught" }, "all exception filters reach dap")
dap.session = function() return nil end
delayed()
t.eq(filters, { "raised", "uncaught" }, "stale exception picker does not change another session")
vim.ui.select, dap.session, dap.set_exception_breakpoints = select, session, set

-- dR and dD act on the root of the session tree. An adapter that owns several
-- targets answers startDebugging with children, and dap.session() follows
-- whichever child last stopped; acting on that child releases one target and
-- leaves the rest attached.
local original_session = dap.session
local restart, set_session = dap.restart, dap.set_session
local root_released, child_released
local tree_root = { children = {}, adapter = {},
  disconnect = function(_, value) root_released = value end }
tree_root.children.child = { children = {}, adapter = {}, parent = tree_root,
  disconnect = function(_, value) child_released = value end }
dap.session = function() return tree_root.children.child end
vim.fn.maparg("<Space>dD", "n", false, true).callback()
t.eq(root_released, { terminateDebuggee = false }, "disconnect reaches the root from a child")
t.eq(child_released, { terminateDebuggee = false }, "disconnect reaches every child in the tree")

local selected, restarted
dap.set_session = function(value) selected = value end
dap.restart = function() restarted = true end
vim.fn.maparg("<Space>dR", "n", false, true).callback()
t.eq(selected, tree_root, "restart selects the root before restarting")
t.ok(restarted, "restart mapping restarts the session")

dap.session = function() return nil end
selected, restarted = nil, nil
vim.fn.maparg("<Space>dR", "n", false, true).callback()
t.eq(restarted, nil, "restart without a session does not reach dap")
dap.restart, dap.set_session = restart, set_session

-- A remote preparation callback may finish after the user switches sessions.
local ready, disconnected, other_disconnected
local first = {
  children = {},
  adapter = { options = { before_disconnect = function(_, done) ready = done end } },
  disconnect = function(_, value) disconnected = value end,
}
dap.session = function() return first end
ui.disconnect()
dap.session = function()
  return { children = {}, adapter = {}, disconnect = function() other_disconnected = true end }
end
ready()
t.eq(disconnected, { terminateDebuggee = false }, "delayed disconnect keeps the originally selected session")
t.eq(other_disconnected, nil, "delayed disconnect does not affect the newly selected session")
disconnected, first.closed = nil, true
ready()
t.eq(disconnected, nil, "closed session is not disconnected a second time")
dap.session = original_session

local dapui = require("dapui")
ui.close_panels()
local editor_tab = vim.api.nvim_get_current_tabpage()
local tabs = #vim.api.nvim_list_tabpages()

-- The debug view owns a tabpage, so the editor layout is never rearranged.
vim.fn.maparg("<Space>du", "n", false, true).callback()
t.eq(#vim.api.nvim_list_tabpages(), tabs + 1, "the debug view opens its own tabpage")
t.ok(vim.api.nvim_get_current_tabpage() ~= editor_tab, "opening the debug view focuses it")
local panels = {}
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  panels[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = true
end
t.ok(panels.dapui_scopes and panels["dap-repl"], "the panels live in the debug tabpage")
t.eq(#vim.api.nvim_tabpage_list_wins(editor_tab), 1, "the editor tabpage is left alone")

vim.fn.maparg("<Space>du", "n", false, true).callback()
t.eq(#vim.api.nvim_list_tabpages(), tabs, "toggling again closes the debug tabpage")
t.eq(vim.api.nvim_get_current_tabpage(), editor_tab, "closing it returns to the editor tabpage")

-- Every child session of a multi-target adapter fires event_initialized, and
-- opening per target re-applies every layout and fights over the tabpage.
dap.listeners.after.event_initialized.dapui_config({ parent = {}, children = {} })
t.eq(#vim.api.nvim_list_tabpages(), tabs, "a child session does not open the debug view")
dap.listeners.after.event_initialized.dapui_config({ children = {} })
t.eq(#vim.api.nvim_list_tabpages(), tabs + 1, "the root session opens the debug view")

-- Stepping stays in the tabpage you are in, and never lands in a panel.
local frame = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(frame, 0, -1, false, { "one", "two", "three" })
local debug_tab = vim.api.nvim_get_current_tabpage()
ui.jump(frame, 2, 1)
t.eq(vim.api.nvim_get_current_tabpage(), debug_tab, "a frame stays inside the debug tabpage")
t.eq(vim.api.nvim_get_current_buf(), frame, "the frame opens in a window a file can go into")
t.eq(vim.bo[vim.api.nvim_get_current_buf()].buftype, "", "the frame never lands in a panel")
t.eq(vim.api.nvim_win_get_cursor(0)[1], 2, "the frame lands on the reported line")

vim.api.nvim_set_current_tabpage(editor_tab)
ui.jump(frame, 3, 1)
t.eq(vim.api.nvim_get_current_tabpage(), editor_tab, "stepping from the editor tabpage stays there")
ui.close_panels()
t.eq(#vim.api.nvim_list_tabpages(), tabs, "ending the session closes the debug tabpage")
ui.open_panels()

-- edgy places the panels, so its slots have to name the filetypes dapui
-- actually sets; `dapui` on its own is not one of them.
-- Config.layout holds the resolved edgebars; Config.options only carries each
-- edge's geometry.
local docked = {}
for edge, edgebar in pairs(require("edgy.config").layout) do
  for _, view in ipairs(edgebar.views or {}) do docked[view.ft] = edge end
end
for ft, edge in pairs({
  dapui_scopes = "left", dapui_breakpoints = "left", dapui_stacks = "left",
  dapui_watches = "left", ["dap-repl"] = "bottom", dapui_console = "bottom",
}) do
  t.eq(docked[ft], edge, "edgy docks " .. ft .. " on the " .. edge)
end

-- dapui's fallback prompts for a target window whenever the tab holds more
-- than one file window, which is this layout's normal shape.
t.eq(require("dapui.config").select_window, require("util.window").ensure_editor_win,
  "stack frames open through the shared editor-window helper")

local sessions = dap.sessions
dap.sessions = function() return { [1] = {} } end
local function settle()
  local done = false
  vim.schedule(function() done = true end)
  vim.wait(1000, function() return done end, 10)
end
dap.listeners.after.event_terminated.dapui_config()
settle()
t.eq(#vim.api.nvim_list_tabpages(), tabs + 1, "ending one session preserves the view for the others")
dap.sessions = function() return {} end
dap.listeners.after.disconnect.dapui_config()
settle()
t.eq(#vim.api.nvim_list_tabpages(), tabs, "last disconnect closes the debug tabpage")
dap.sessions = sessions
-- A sign whose texthl/linehl/numhl names a group nothing defines fails
-- silently: the sign still places, the highlight simply does nothing. That is
-- how the stopped line went unmarked -- `DapStoppedLine` was named twice and
-- never created, leaving the gutter arrow as the only sign execution had
-- paused there.
for _, name in ipairs({ "DapStopped", "DapBreakpoint", "DapBreakpointCondition",
                        "DapBreakpointRejected", "DapLogPoint" }) do
  local sign = vim.fn.sign_getdefined(name)[1]
  t.ok(sign ~= nil, name .. " is defined")
  -- The Dap sign segment in lua/plugin/ui/statuscol.lua sets `maxwidth = 1`,
  -- which truncates a wider glyph without saying so -- that is how the
  -- two-cell `.>` logpoint had been rendering as a bare dot.
  local text = sign and vim.trim(sign.text or "")
  if text then
    t.eq(vim.fn.strwidth(text), 1, ("%s renders in the one cell the gutter gives it"):format(name))
  end
  for _, attr in ipairs({ "texthl", "linehl", "numhl" }) do
    local group = sign and sign[attr]
    if group then
      t.ok(next(vim.api.nvim_get_hl(0, { name = group, link = false })) ~= nil,
        ("%s %s -> %s is a real highlight"):format(name, attr, group))
    end
  end
end

-- The <leader>d and <leader>t popups read like every other group: sentence
-- case, verb first, and "…" on exactly the keys that ask before they act
-- (typed input or a choice).
for suffix, want in pairs({
  dA = "Attach to running target…", dB = "Set conditional breakpoint…", dC = "Run to cursor",
  dD = "Disconnect (keep target running)", dL = "Set logpoint…", dO = "Step over", dP = "Pause",
  dR = "Restart session", dW = "Add watch expression…", da = "Run with args…", db = "Toggle breakpoint",
  dc = "Run/continue", de = "Set exception breakpoints…", df = "Debug file", dg = "Go to line (no execute)",
  di = "Step into", dj = "Stack frame down", dk = "Stack frame up", dl = "Run last", ["do"] = "Step out",
  dq = "List breakpoints (quickfix)", dr = "Toggle REPL", ds = "Debug sessions", dt = "Terminate",
  du = "Toggle debug view", dw = "Evaluate expression", dx = "Clear all breakpoints",
  tm = "Run nearest test", tM = "Debug nearest test", tf = "Run tests in file", tF = "Debug tests in file",
  ts = "Toggle test summary", to = "Show test output", tx = "Toggle test diagnostics",
}) do
  t.eq(vim.fn.maparg("<leader>" .. suffix, "n", false, true).desc, want, "<leader>" .. suffix .. " is " .. want)
end
-- Case is the debug variant of the same run (tm/tM, tf/tF); the summary is ts,
-- and test diagnostics are one toggle, not a show key and a hide key.
for _, suffix in ipairs({ "td", "tD", "th", "tS" }) do
  t.eq(vim.fn.maparg("<leader>" .. suffix, "n"), "", "<leader>" .. suffix .. " is gone")
end
-- neotest has no show/hide of its own diagnostics: <leader>tx toggles their
-- namespace, whose disabled flag is the state.
require("lazy").load({ plugins = { "neotest" } })
local test_ns = vim.api.nvim_create_namespace("neotest")
local toggle_test_diagnostics = vim.fn.maparg("<leader>tx", "n", false, true).callback
toggle_test_diagnostics()
t.eq(vim.diagnostic.get_namespace(test_ns).disabled, true, "<leader>tx hides test diagnostics")
toggle_test_diagnostics()
t.eq(vim.diagnostic.get_namespace(test_ns).disabled, false, "<leader>tx shows them again")
t.eq(vim.fn.maparg("<leader>dw", "x", false, true).desc, "Evaluate selection",
  "Visual <leader>dw names the selection it evaluates")
-- Read through :command, which prints the desc as given. nvim_get_commands()
-- returns it with the 0x80 byte of "…" escaped (K_SPECIAL), so it never matches.
t.ok(vim.api.nvim_exec2("command DapAttach", { output = true }).output:find("Attach to running target…", 1, true),
  ":DapAttach is described like <leader>dA")

t.done()
