-- The session registry owns identity; providers own opaque PTY/view handles.
local M = {}
local sessions, generation = {}, 0
local api = vim.api
local function implementation()
  local selected = require("agent_workbench.options").get().terminal.provider
  if type(selected) == "string" then return require("agent_workbench.provider." .. selected) end
  for _, method in ipairs({ "open", "show", "hide", "send", "alive", "stop" }) do
    assert(type(selected[method]) == "function", "terminal provider missing " .. method)
  end
  return selected
end
local function event()
  api.nvim_exec_autocmds("User", { pattern = "AgentWorkbenchSessionChanged", modeline = false })
end
function M.open(kind, request)
  assert(sessions[kind] == nil or not M.alive(sessions[kind]), "native session is already running")
  if sessions[kind] then M.stop(sessions[kind]) end
  generation = generation + 1
  local session = { id = "native:" .. kind, kind = kind, generation = generation, root = request.cwd, provider = implementation() }
  sessions[kind] = session
  request = vim.tbl_extend("force", request, {
    on_buffer = function(buf)
      session.buf = buf
      vim.b[buf].agent_workbench = {
        id = session.id, kind = kind, generation = session.generation, cwd = request.cwd, cmd = request.argv,
      }
    end,
    on_exit = function(code)
      session.exit_code = code
      if sessions[kind] == session then event() end
    end,
  })
  local ok, handle, err = pcall(session.provider.open, request)
  if not ok or not handle then
    if sessions[kind] == session then sessions[kind] = nil end
    error(not ok and handle or (err and err.message or "Terminal provider failed"), 0)
  end
  session.handle, session.request = handle, request
  session.buf = session.buf or handle.buf
  event()
  return session
end
function M.alive(session)
  return session and session.handle ~= nil and session.provider.alive(session.handle) == true or false
end
function M.window(session)
  local handle = session and session.handle
  local win = handle and handle.win
  if win and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == session.buf then return win end
end
function M.show(session)
  return session.provider.show(session.handle, session.request)
end
function M.hide(session)
  local win = M.window(session)
  if not win then return true end
  local tab = api.nvim_win_get_tabpage(win)
  if tab ~= api.nvim_get_current_tabpage() then return false, { code = "other_tab", message = "View belongs to another tab" } end
  local count = 0
  for _, w in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if api.nvim_win_get_config(w).relative == "" then count = count + 1 end
  end
  if count <= 1 then return false, { code = "only_window", message = "Cannot hide the only normal window" } end
  return session.provider.hide(session.handle, tab)
end
function M.send(session, bytes) return session.provider.send(session.handle, bytes) end
function M.stop(session)
  if not session then return true end
  if session.handle then session.provider.stop(session.handle) end
  if sessions[session.kind] == session then sessions[session.kind] = nil end
  event()
  return true
end
function M.session(kind)
  local s = sessions[kind]
  if not s then return nil end
  return { id = s.id, kind = s.kind, generation = s.generation, root = s.root,
    buf = s.buf, win = M.window(s), alive = M.alive(s), exit_code = s.exit_code }
end
function M.sessions()
  local result = {}
  for kind in pairs(sessions) do result[#result + 1] = M.session(kind) end
  table.sort(result, function(a, b) return a.id < b.id end)
  return result
end
return M
