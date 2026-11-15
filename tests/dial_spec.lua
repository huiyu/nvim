local t = dofile("tests/helper.lua")
local a = vim.api

vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.wait(100, function() return false end, 10)

local function press(keys)
  a.nvim_feedkeys(a.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

-- JS/TS declarations share Dial's ordinary groups; whole words and unrelated
-- filetypes must retain their previous behavior.
for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact", "lua" }) do
  vim.cmd.enew()
  vim.bo.filetype = ft
  a.nvim_buf_set_lines(0, 0, -1, false, { "let value", "letter", "true", "2026-09-10" })
  a.nvim_win_set_cursor(0, { 1, 0 })
  press("<C-a>")
  t.eq(a.nvim_get_current_line(), ft == "lua" and "let value" or "const value",
    ft .. ": declaration toggle stays language-scoped")
  if ft ~= "lua" then
    press("<C-x>")
    t.eq(a.nvim_get_current_line(), "let value", ft .. ": decrement toggles back")
  end
  a.nvim_win_set_cursor(0, { 2, 0 })
  press("<C-a>")
  t.eq(a.nvim_get_current_line(), "letter", ft .. ": identifiers are not rewritten")
  a.nvim_win_set_cursor(0, { 3, 0 })
  press("<C-a>")
  t.eq(a.nvim_get_current_line(), "false", ft .. ": boolean toggle is retained")
  a.nvim_win_set_cursor(0, { 4, 9 })
  press("<C-a>")
  t.eq(a.nvim_get_current_line(), "2026-09-11", ft .. ": date increment is retained")
  vim.bo.modified = false
end

t.done()
