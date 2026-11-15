-- Neovim PTY and split ownership. No host/plugin dependency.
local M = {}
local api = vim.api
function M.show(handle, request)
  if handle.win and api.nvim_win_is_valid(handle.win) and api.nvim_win_get_buf(handle.win) == handle.buf then
    api.nvim_set_current_win(handle.win)
    return handle.win
  end
  handle.win = api.nvim_open_win(handle.buf, true, { split = "right", width = request.width })
  request.on_view(handle.win)
  vim.wo[handle.win].winfixwidth = true
  vim.wo[handle.win].winbar = ""
  return handle.win
end
function M.open(request)
  local handle = { buf = api.nvim_create_buf(false, true) }
  vim.bo[handle.buf].bufhidden = "hide"
  request.on_buffer(handle.buf)
  local ok, err = pcall(function()
    M.show(handle, request)
    api.nvim_buf_call(handle.buf, function()
      handle.channel = vim.fn.jobstart(request.argv, {
        term = true, cwd = request.cwd, env = request.env,
        on_exit = function(_, code)
          request.on_exit(code)
          if code == 0 then
            vim.schedule(function()
              if api.nvim_buf_is_valid(handle.buf) then api.nvim_buf_delete(handle.buf, { force = true }) end
            end)
          end
        end,
      })
    end)
    assert(handle.channel > 0, "Neovim terminal process could not start")
  end)
  if not ok then
    if api.nvim_buf_is_valid(handle.buf) then api.nvim_buf_delete(handle.buf, { force = true }) end
    return nil, { code = "unavailable", message = tostring(err) }
  end
  vim.bo[handle.buf].filetype = "agent_terminal"
  return handle
end
function M.hide(handle)
  api.nvim_win_close(handle.win, true)
  handle.win = nil
  return true
end
function M.send(handle, bytes)
  if not M.alive(handle) then return false, { code = "exited", message = "Terminal process has exited" } end
  api.nvim_chan_send(handle.channel, bytes)
  return true
end
function M.alive(handle)
  return handle.channel ~= nil and vim.fn.jobwait({ handle.channel }, 0)[1] == -1
end
function M.stop(handle)
  if M.alive(handle) then vim.fn.jobstop(handle.channel) end
  if handle.buf and api.nvim_buf_is_valid(handle.buf) then api.nvim_buf_delete(handle.buf, { force = true }) end
  return true
end
return M
