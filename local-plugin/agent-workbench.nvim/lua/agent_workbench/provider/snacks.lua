-- The only native-agent module that knows Snacks terminal objects.
local M = {}
function M.open(request)
  local ok, snacks = pcall(require, "snacks")
  if not ok then return nil, { code = "unavailable", message = "Selected Snacks terminal provider is not installed" } end
  local handle = {}
  local terminal = snacks.terminal.open(request.argv, {
    cwd = request.cwd, env = request.env, auto_insert = true, start_insert = true, auto_close = false,
    win = {
      position = "right", width = request.width, bo = { filetype = "agent_terminal" },
      wo = { winfixwidth = true, winbar = "" },
      keys = { term_normal = false },
      on_buf = function(win)
        request.on_buffer(win.buf)
        vim.api.nvim_create_autocmd("TermClose", {
          buffer = win.buf, once = true, callback = function()
            local code = vim.v.event.status
            request.on_exit(code)
            if code == 0 then
              vim.schedule(function() win:close() end)
            elseif not handle.stopping then
              vim.notify("Terminal exited with code " .. code, vim.log.levels.WARN)
            end
          end,
        })
      end,
      on_win = function(win) request.on_view(win.win) end,
    },
  })
  handle.buf, handle.channel, handle.win, handle.terminal = terminal.buf, vim.bo[terminal.buf].channel, terminal.win, terminal
  return handle
end
function M.show(handle, request)
  handle.terminal:show():focus()
  handle.win = handle.terminal.win
  request.on_view(handle.win)
  return handle.win
end
function M.hide(handle)
  handle.terminal:hide()
  handle.win = nil
  return true
end
M.send = require("agent_workbench.provider.native").send
M.alive = require("agent_workbench.provider.native").alive
function M.stop(handle)
  handle.stopping = true
  if M.alive(handle) then vim.fn.jobstop(handle.channel) end
  handle.terminal:close()
  return true
end
return M
