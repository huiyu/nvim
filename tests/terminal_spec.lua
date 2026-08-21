-- Guards the terminal identity and position contracts.
--
-- Identity: `<leader>T1`..`T9` silently shared one terminal for a long time.
-- Snacks derives identity from cmd/cwd/env/count and never reads `opts.id`, so
-- passing name strings looked right and did nothing.
--
-- Position: chosen once by vim.g.terminal_position, never toggled at runtime.
-- edgy has to agree with that choice or it docks what should float.
local t = dofile("tests/helper.lua")
local term = require("util.terminal")

-- edgy claims every non-agent snacks_terminal for its bottom edge, so it must
-- be loaded before any float is judged. It normally arrives on VeryLazy, which
-- never fires headless -- which is exactly why an earlier version of this spec
-- passed while the float still docked itself in a real session.
vim.cmd("Lazy! load edgy.nvim")
t.ok(package.loaded["edgy"] ~= nil, "edgy is loaded, so its layout rules apply")

local function relative_of(win)
  return vim.api.nvim_win_get_config(win).relative
end

-- Numbered terminals must actually be distinct.
term.toggle(1)
local one = vim.api.nvim_get_current_buf()
term.toggle(1) -- hide
term.toggle(2)
local two = vim.api.nvim_get_current_buf()
t.ok(one ~= two, "<leader>T1 and <leader>T2 are different terminals")
t.eq(vim.bo[one].buftype, "terminal", "terminal 1 is a real terminal")
term.toggle(2) -- hide

-- Re-toggling a number returns to the same shell rather than spawning another.
term.toggle(1)
t.eq(vim.api.nvim_get_current_buf(), one, "toggling a number reuses its shell")

-- Position is configuration, not a runtime toggle. Whatever it is set to, that
-- is the shape terminals open in -- and edgy must agree, or a float gets docked.
local floats = term.floats()
t.eq(floats, vim.g.terminal_position ~= "bottom", "floats() follows vim.g.terminal_position")

-- Terminal 1 is already showing from the check above; toggling again would
-- hide it.
vim.wait(400, function() return false end)
local win = vim.fn.bufwinid(one)
t.ok(win ~= -1, "terminal 1 is visible")
t.eq(relative_of(win) ~= "", floats,
  floats and "terminals open floating" or "terminals open docked")

-- An unnumbered toggle -- what <C-/> does -- must act on the terminal you are
-- sitting in. Defaulting to terminal 1 meant pressing it inside terminal 3
-- hid, or jumped to, a different terminal entirely.
term.toggle(3)
local three = vim.api.nvim_get_current_buf()
t.ok(three ~= one and three ~= two, "terminal 3 is its own shell")

local one_visible_before = vim.fn.bufwinid(one) ~= -1
term.toggle() -- <C-/> while sitting in terminal 3
t.eq(vim.fn.bufwinid(three), -1, "<C-/> hides the terminal you are in")
t.eq(vim.fn.bufwinid(one) ~= -1, one_visible_before,
  "<C-/> leaves other terminals exactly as they were")

-- From a normal buffer there is no "current terminal", so it reopens the one
-- you were last in -- which at this point is terminal 3.
vim.cmd("topleft new")
t.eq(vim.bo.buftype, "", "sitting in a normal buffer")
term.toggle()
vim.wait(300, function() return false end)
t.eq(vim.api.nvim_get_current_buf(), three,
  "from the editor, <C-/> reopens the terminal you were last in")

-- Closing a terminal and reopening must return to the one you were in. Falling
-- back to terminal 1 meant every close-reopen cycle threw away where you were.
local function current_id()
  local buf = vim.api.nvim_get_current_buf()
  local info = vim.b[buf].snacks_terminal
  return info and info.id or nil
end

-- Start from a known state: earlier blocks may have left terminal 3 showing.
if vim.fn.bufwinid(three) ~= -1 then term.toggle(3) end
term.toggle(3)
t.eq(current_id(), 3, "terminal 3 is open")
term.toggle() -- close it
t.eq(current_id(), nil, "and closed again")
term.toggle() -- reopen
t.eq(current_id(), 3, "reopening returns to the terminal you were last in")

-- An explicit count still wins over that memory.
term.toggle()
vim.api.nvim_feedkeys(vim.keycode("2"), "n", false)
term.toggle(2)
t.eq(current_id(), 2, "an explicit count overrides the remembered terminal")
term.toggle()

-- <leader>t1..t9 pick which terminal you are looking at; they never close one.
-- Pressing the number of the terminal you are already in used to dismiss it,
-- which made the numbers a second, competing close key.
term.focus(1)
t.eq(current_id(), 1, "focus opens terminal 1")
term.focus(1)
t.eq(current_id(), 1, "focusing the terminal you are already in keeps it open")
term.focus(1)
t.eq(current_id(), 1, "and stays open however many times you press it")

term.focus(2)
t.eq(current_id(), 2, "focus switches to another terminal")
t.eq(vim.fn.bufwinid(one), -1, "and puts the previous float away")

-- Closing remains <C-/>'s single job, and it acts on whatever focus left you in.
term.toggle()
t.eq(current_id(), nil, "<C-/> is still the one thing that closes a terminal")
term.toggle()
t.eq(current_id(), 2, "and reopens the terminal focus last chose")
term.toggle()

-- A visible-but-unfocused terminal should be stepped into, not dismissed:
-- closing a window you are not looking at is a surprise, and pressing again
-- from inside it closes it anyway.
term.focus(1)
vim.cmd("topleft new")
t.eq(vim.bo.buftype, "", "sitting in the editor with terminal 1 still showing")
term.toggle()
t.eq(current_id(), 1, "<C-/> steps into a visible terminal rather than closing it")
term.toggle()
t.eq(current_id(), nil, "pressing it again, now from inside, closes it")

-- A float has no tabline or statusline to say which terminal it is, and Snacks
-- leaves float titles empty. Without the number they are indistinguishable.
if term.floats() then
  local function title_of(buf)
    local w = vim.fn.bufwinid(buf)
    if w == -1 then return nil end
    local cfg = vim.api.nvim_win_get_config(w)
    return type(cfg.title) == "table" and cfg.title[1][1] or cfg.title
  end

  term.toggle(4)
  local four = vim.api.nvim_get_current_buf()
  t.ok((title_of(four) or ""):find("4", 1, true) ~= nil,
    "the float's border names which terminal it is")

  -- Shells announce the running command through an OSC title sequence.
  vim.api.nvim_chan_send(vim.bo[four].channel, "printf '\\033]2;spec-task\\007'\r")
  vim.wait(2000, function() return (title_of(four) or ""):find("spec%-task") ~= nil end)
  t.ok((title_of(four) or ""):find("spec-task", 1, true) ~= nil,
    "the title follows what the shell says is running")

  -- Floats stack, so opening another must put the previous one away, or closing
  -- the top one just reveals the one behind it.
  term.toggle(5)
  t.eq(vim.fn.bufwinid(four), -1, "opening another float puts the previous one away")
  term.toggle() -- <C-/> in terminal 5
  t.eq(vim.bo[vim.api.nvim_get_current_buf()].buftype, "",
    "one <C-/> leaves the terminals entirely, with none revealed behind")
end

t.done()
