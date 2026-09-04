-- Guards <leader>qq actually quitting Nvim from inside an agent panel.
--
-- Snacks closes each of its terminal windows from its own `ExitPre`, and Nvim
-- refuses to finish a quit whose autocommands closed a window -- so `:qall`
-- run from inside the Claude/Codex panel closed the panel and left Nvim
-- running. The failure was silent: no error, no message, just an editor that
-- did not quit.
local t = dofile("tests/helper.lua")
local win = require("util.window")

-- The real quit would take the spec down with it, so the command is captured
-- through the module's own indirection instead of being run.
local issued = {}
local real_quit = win._quit
win._quit = function(command) issued[#issued + 1] = command end

local function open_terminal()
  local term = require("snacks").terminal.open({ "cat" }, {
    win = { position = "right", width = 0.3 },
  })
  vim.wait(2000, function() return vim.bo[term.buf].buftype == "terminal" end)
  return term
end

-- Asserted against the spec data rather than the live keymap: which-key queues
-- its mappings until a scheduled load that never runs headless, so the keymap
-- itself is not observable here -- but the data that produces it is.
local function quit_entry(lhs)
  for _, entry in ipairs(require("whichkey_spec")) do
    if entry[1] == lhs then return entry end
  end
end

-- `<cmd>qall<cr>` is exactly the form Snacks' ExitPre swallows.
for _, lhs in ipairs({ "<leader>qq", "<leader>qQ" }) do
  local entry = quit_entry(lhs)
  t.ok(entry ~= nil, lhs .. " is still in the which-key spec")
  t.eq(type(entry and entry[2]), "function", lhs .. " goes through quit_all, not a bare :qall")
end

-- A Snacks terminal has to be gone before the quit is issued, or ExitPre will
-- close its window mid-quit and Nvim will drop the quit.
local term = open_terminal()
local term_buf, term_win = term.buf, term.win
t.ok(vim.b[term_buf].snacks_terminal ~= nil, "the terminal is Snacks-managed")

win.quit_all()
t.eq(issued, { "qall" }, "quit_all issues :qall")
t.ok(not vim.api.nvim_win_is_valid(term_win), "the Snacks terminal window is closed first")
-- The buffer is left to ExitPre on purpose: a Snacks terminal that is merely
-- hidden never blocked the quit, so only the window has to go.
t.ok(vim.api.nvim_buf_is_valid(term_buf), "its buffer is left alone")

issued = {}
local forced = open_terminal()
local forced_win = forced.win
win.quit_all(true)
t.eq(issued, { "qall!" }, "the forcing variant issues :qall!")
t.ok(not vim.api.nvim_win_is_valid(forced_win), "which also closes the terminal window")

-- Closing the panel is not free, so a quit Nvim is going to refuse must not do
-- it. Nor may it issue :qall and leave the refusal to Nvim: ExitPre closes the
-- panel before Nvim looks at modified buffers, and from inside the panel the
-- quit is then dropped without a word. The refusal is a message of our own.
issued = {}
local kept = open_terminal()
local kept_win = kept.win
local dirty = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(dirty, "unsaved-file.txt")
vim.api.nvim_buf_set_lines(dirty, 0, -1, false, { "unsaved" })
t.eq(vim.bo[dirty].modified, true, "there is an unsaved buffer")

local notified = {}
local real_notify = vim.notify
vim.notify = function(msg, level) notified[#notified + 1] = { msg = msg, level = level } end

win.quit_all()
t.eq(issued, {}, "an unsaved buffer refuses the quit without issuing :qall")
t.ok(vim.api.nvim_win_is_valid(kept_win), "and the agent panel survives the refusal")
t.eq(#notified, 1, "the refusal is a single notification")
t.eq(notified[1] and notified[1].level, vim.log.levels.WARN, "at WARN level")
t.ok(notified[1] and notified[1].msg:find("unsaved-file.txt", 1, true) ~= nil,
  "which names the unsaved buffer")
t.ok(notified[1] and notified[1].msg:find("<leader>qQ", 1, true) ~= nil,
  "and points at the forcing variant")

-- ...but the forcing variant is the user saying they mean it.
issued, notified = {}, {}
win.quit_all(true)
t.eq(issued, { "qall!" }, "qall! is issued even with unsaved buffers")
t.eq(#notified, 0, "without a notification")
t.ok(not vim.api.nvim_win_is_valid(kept_win), "and it does close the terminal window")
vim.bo[dirty].modified = false

-- Which buffers count is Nvim's own rule, not `buftype == ""`: an acwrite
-- buffer (oil) blocks the quit like a file, while a scratch buffer carries the
-- raw changed flag permanently and never blocks it.
local acwrite = vim.api.nvim_create_buf(true, false)
vim.bo[acwrite].buftype = "acwrite"
vim.api.nvim_buf_set_lines(acwrite, 0, -1, false, { "pending" })
issued, notified = {}, {}
win.quit_all()
t.eq(issued, {}, "a modified acwrite buffer refuses the quit")
t.eq(#notified, 1, "with the same notification")
vim.bo[acwrite].modified = false

local scratch = vim.api.nvim_create_buf(true, false)
vim.bo[scratch].buftype = "nofile"
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "scratch" })
local listed = vim.tbl_map(function(info) return info.bufnr end, vim.fn.getbufinfo({ bufmodified = 1 }))
t.ok(vim.list_contains(listed, scratch), "getbufinfo() lists a scratch buffer as modified")
issued, notified = {}, {}
win.quit_all()
t.eq(issued, { "qall" }, "but it does not block the quit")
t.eq(#notified, 0, "and raises no notification")

vim.notify = real_notify
win._quit = real_quit
t.done()
