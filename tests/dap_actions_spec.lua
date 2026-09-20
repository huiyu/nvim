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
dapui.close()
local windows = #vim.api.nvim_tabpage_list_wins(0)
vim.fn.maparg("<Space>du", "n", false, true).callback()
t.ok(#vim.api.nvim_tabpage_list_wins(0) > windows, "panels can be reopened manually")
vim.fn.maparg("<Space>du", "n", false, true).callback()
t.eq(#vim.api.nvim_tabpage_list_wins(0), windows, "panel toggle closes the panels again")
dapui.open()
local sessions = dap.sessions
dap.sessions = function() return { [1] = {} } end
local function settle()
  local done = false
  vim.schedule(function() done = true end)
  vim.wait(1000, function() return done end, 10)
end
dap.listeners.after.event_terminated.dapui_config()
settle()
t.ok(#vim.api.nvim_tabpage_list_wins(0) > windows, "ending one session preserves panels for other sessions")
dap.sessions = function() return {} end
dap.listeners.after.disconnect.dapui_config()
settle()
t.eq(#vim.api.nvim_tabpage_list_wins(0), windows, "last disconnect closes panels")
dap.sessions = sessions
t.done()
