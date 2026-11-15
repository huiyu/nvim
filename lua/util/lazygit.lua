-- Lazygit uses its own terminal input rules and floating window. Requiring
-- this module does not start a terminal or install mappings.
local M = {}

---@param file? string show this file's history instead of the repository
function M.open(file)
  local cmd = file and { "lazygit", "log", "--filter", file } or "lazygit"
  return Snacks.terminal(cmd, {
    cwd = Snacks.git.get_root(),
    interactive = true,
    win = {
      style = "float", width = 0.9, height = 0.9,
      on_buf = function(win)
        -- j must be immediate; an already-buffered jk must pass through too.
        -- nowait alone cannot beat a complete global chord in the typeahead;
        -- define j last so it is found before the local jk partial match.
        for _, key in ipairs({ "jk", "j" }) do
          vim.keymap.set("t", key, key, {
            buffer = win.buf, nowait = true, desc = "Send " .. key .. " to Lazygit",
          })
        end
      end,
    },
  })
end

return M
