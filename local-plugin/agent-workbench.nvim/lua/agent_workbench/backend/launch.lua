-- Native-agent launch support. Requiring this module starts nothing: each
-- backend calls ensure_watchdog only when its own terminal is first used.
local M = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
function M.script(name) return root .. "/scripts/" .. name end

---An opt-out preference with environment > vim.g > enabled precedence.
---@param env_name string
---@param global_name string
---@return boolean
function M.enabled(env_name, global_name)
  local value = vim.env[env_name]
  if value == "1" or value == "true" then return true end
  if value == "0" or value == "false" then return false end
  if vim.g[global_name] ~= nil then return vim.g[global_name] ~= false end
  local kind = env_name:match("^(.-)_WRAP_TMUX$")
  local native = kind and require("agent_workbench.options").get().native[kind:lower()]
  return not native or native.wrap_tmux ~= false
end

---Path to the $EDITOR wrapper the agent terminals are launched with.
---@return string
function M.wrapper()
  return M.script("agent-editor")
end

---Launcher that keeps a failed agent's error on screen instead of letting the
---panel vanish. Used as the pane command inside both tmux wrappers -- see
---local-plugin/agent-workbench.nvim/scripts/agent-run for why the exit status cannot be recovered on this side.
---@return string
function M.runner()
  return M.script("agent-run")
end

---Absolute path to local-plugin/agent-workbench.nvim/scripts/agent-teardown. Both wrappers run it from their
---`client-detached` hook and their watchdog: it records the pane's process tree
---before the tmux server goes and sweeps whatever of it survives, so quitting
---Nvim no longer leaves the agent's background jobs running with ppid 1.
---@return string
function M.teardown()
  return M.script("agent-teardown")
end

---The tmux command both wrappers install as their `client-detached` hook: run
---agent-teardown for `socket` detached, or -- should the script be missing --
---fall back to a bare kill-server, so the server never outlives its client
---either way. Kept in one place because the Codex wrapper passes it as a
---single argv entry while the Claude one re-quotes it for `sh -c`; the inner
---quotes are single so the tmux double quotes around them stay untouched.
---@param socket string the wrapper server's `-L` name
---@return string
function M.teardown_hook(socket)
  local sh = vim.fn.shellescape(M.teardown()) .. " " .. socket
    .. " || tmux -L " .. socket .. " kill-server"
  return 'run-shell -b "' .. sh .. '"'
end

---Environment for the TUI's ctrl+g handoff, including without tmux. A tmux
---pane also needs these values explicitly forwarded through new-session -e.
---@return table<string, string>
function M.editor_env()
  local wrapper = M.wrapper()
  return { EDITOR = wrapper, VISUAL = wrapper, NVIM = vim.v.servername }
end

-- A detached watchdog covers exits where client-detached cannot run (Nvim
-- killed outright or the host terminal torn down), and sweeps stale wrapper
-- servers from earlier crashes. Teardown runs synchronously so a socket only
-- goes once the server and the agent's leftover process tree are gone.
local watchdog_started = {}

---@param agent "claude"|"codex"
function M.ensure_watchdog(agent)
  if watchdog_started[agent] then return end
  watchdog_started[agent] = true

  local pid = vim.fn.getpid()
  local prefix = agent .. "-nvim-"
  local socket = prefix .. pid
  local teardown = vim.fn.shellescape(M.teardown())
  local script = string.format([[
    for s in /private/tmp/tmux-*/%s* /tmp/tmux-*/%s*; do
      [ -e "$s" ] || continue
      case $s in *.lock) continue ;; esac   # tmux's lock file beside the socket
      owner=${s##*%s}
      if ! kill -0 "$owner" 2>/dev/null; then
        %s --wait "$s" || tmux -S "$s" kill-server 2>/dev/null
        rm -f "$s"
      fi
    done
    while kill -0 %d 2>/dev/null; do sleep 2; done
    %s --wait %s || tmux -L %s kill-server 2>/dev/null
    rm -f /private/tmp/tmux-*/%s /tmp/tmux-*/%s
  ]], prefix, prefix, prefix, teardown, pid, teardown, socket, socket, socket, socket)
  -- detach calls setsid, surviving the SIGHUP cascade through Nvim's group.
  vim.fn.jobstart({ "sh", "-c", script }, { detach = true })
end

return M
