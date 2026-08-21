-- Guards the terminal identity and shape contracts.
--
-- Identity: `<leader>T1`..`T9` silently shared one terminal for a long time.
-- Snacks derives identity from cmd/cwd/env/count and never reads `opts.id`, so
-- passing name strings looked right and did nothing.
--
-- Shape: floating is a property of a terminal, not a separate terminal. The
-- same shell, buffer and window handle survive the switch.
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

-- Floating a terminal that does not exist yet must open it floating, never
-- open it docked and move it. Creating-then-converting is what made the bottom
-- terminal flash into view for a frame first.
do
  local docked_seen = false
  local group = vim.api.nvim_create_augroup("terminal_spec_flash", { clear = true })
  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(ev)
      local win = vim.fn.bufwinid(ev.buf)
      if win ~= -1 and vim.api.nvim_win_get_config(win).relative == "" then
        docked_seen = true
      end
    end,
  })

  term.toggle_float(9) -- a number nothing else in this spec touches
  vim.wait(300, function() return false end)
  t.ok(not docked_seen, "a first-time float never appears docked, not even for one frame")
  t.eq(relative_of(vim.api.nvim_get_current_win()), "editor", "it opens floating")
  vim.api.nvim_del_augroup_by_id(group)
  term.toggle_float(9) -- dock it so it cannot interfere below
  term.toggle(9)       -- and hide it
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

-- Floating acts on the terminal you are in, and changes only its shape.
local before_win = vim.api.nvim_get_current_win()
t.eq(relative_of(before_win), "", "terminal 1 starts docked")

term.toggle_float()
local float_win = vim.api.nvim_get_current_win()
t.eq(relative_of(float_win), "editor", "toggle_float floats the terminal")
-- The window is rebuilt, which is how Snacks applies the new shape. What must
-- survive is the shell, not the window handle.
t.eq(vim.api.nvim_win_get_buf(float_win), one, "floating keeps the same shell")
t.ok(term.is_float_buf(one), "the floating terminal is marked for edgy")

-- edgy docks asynchronously; it must leave a marked float alone.
vim.wait(300, function() return false end)
t.ok(vim.api.nvim_win_is_valid(float_win), "the float survives edgy's layout pass")
t.eq(relative_of(float_win), "editor", "edgy does not dock the float")

-- And back again.
term.toggle_float()
t.eq(relative_of(vim.api.nvim_get_current_win()), "", "toggling again re-docks it")
t.eq(vim.api.nvim_get_current_buf(), one, "re-docking keeps the same shell")
t.ok(not term.is_float_buf(one), "the mark is cleared once docked")

-- Shape belongs to the terminal, not to the window showing it. Snacks only
-- remembers the config a terminal was created with, so without a record of its
-- own a float would silently drop back to the bottom on every hide/show.
term.toggle_float()
t.eq(relative_of(vim.api.nvim_get_current_win()), "editor", "floated again")
term.toggle(1) -- hide
term.toggle(1) -- show
vim.wait(400, function() return false end)
local reshown = vim.fn.bufwinid(one)
t.ok(reshown ~= -1, "the terminal is visible again")
t.eq(relative_of(reshown), "editor", "a floated terminal comes back floating")
t.ok(term.is_float_buf(one), "and stays marked so edgy leaves it alone")

-- Docking it must stick the same way.
vim.api.nvim_set_current_win(reshown)
term.toggle_float()
t.eq(relative_of(vim.api.nvim_get_current_win()), "", "docked again")
term.toggle(1) -- hide
term.toggle(1) -- show
vim.wait(400, function() return false end)
local redocked = vim.fn.bufwinid(one)
t.eq(relative_of(redocked), "", "a docked terminal comes back docked")
t.ok(not term.is_float_buf(one), "and carries no float mark")

-- Opening a second terminal must not disturb a floating first one.
vim.api.nvim_set_current_win(redocked)
term.toggle_float()
t.eq(relative_of(vim.api.nvim_get_current_win()), "editor", "terminal 1 floating once more")
term.toggle(2)
vim.wait(400, function() return false end)
t.eq(relative_of(vim.fn.bufwinid(one)), "editor", "opening terminal 2 leaves the float alone")
t.eq(relative_of(vim.fn.bufwinid(two)), "", "and terminal 2 opens docked")
vim.api.nvim_set_current_win(vim.fn.bufwinid(one))
term.toggle_float() -- back to docked for the checks below

-- From the editor, the count decides which terminal is acted on.
-- A fresh window is needed, not `enew`: edgy owns the terminal's window and
-- keeps a terminal in it, so swapping the buffer in place does not get us out.
vim.cmd("topleft new")
t.eq(vim.bo.buftype, "", "now sitting in a normal buffer, not a terminal")
term.toggle_float(2)
t.eq(vim.api.nvim_get_current_buf(), two, "a count targets that terminal from the editor")
t.eq(relative_of(vim.api.nvim_get_current_win()), "editor", "and floats it")
term.toggle_float(2)

t.done()
