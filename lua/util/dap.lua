-- Small UI helpers shared by every debug adapter. Nothing loads dap at startup.
local M = {}

-- Language modules contribute callbacks through nvim-dap's opts.targets.
M.targets = {}

---Prompt for an attach option. Empty input and cancellation abort the launch.
function M.input(prompt, default)
  local ok, value = pcall(vim.fn.input, { prompt = prompt, default = default or "" })
  if not ok or vim.trim(value) == "" then return require("dap").ABORT end
  return vim.trim(value)
end

function M.port(default)
  local value = M.input("Debug port: ", tostring(default))
  if value == require("dap").ABORT then return value end
  local port = tonumber(value)
  if not port or port % 1 ~= 0 or port < 1 or port > 65535 then
    vim.notify("Debug port must be an integer from 1 to 65535", vim.log.levels.WARN)
    return require("dap").ABORT
  end
  return port
end

-- The debug view owns a tabpage of its own, the way diffview does: starting a
-- session should not rearrange the windows you were editing in, and ending one
-- should hand that layout back untouched.
--
-- Stepping stays in whichever tabpage you are in. Both halves of that are
-- deliberate: `M.jump` below never leaves the current tabpage, so going back to
-- the editor tab mid-session keeps working and the panels update out of sight
-- until you return. Following you across tabs would make the debug view able to
-- steal focus from an editor tab, which is more intrusive than the split layout
-- it replaced.
local debug_tab = nil

local function debug_tab_valid()
  return debug_tab ~= nil and vim.api.nvim_tabpage_is_valid(debug_tab)
end

---Open the debug view, creating its tabpage on first use, and focus it.
function M.open_panels()
  if debug_tab_valid() then
    vim.api.nvim_set_current_tabpage(debug_tab)
  else
    -- `tab split` rather than `tabnew`: the tab starts on the file the session
    -- was launched from, which is where the first breakpoint lands. Launching
    -- from a panel duplicates that panel instead, which `M.jump` heals on the
    -- first stop by opening a file window in this tab.
    vim.cmd("tab split")
    debug_tab = vim.api.nvim_get_current_tabpage()
  end
  require("dapui").open({})
end

---Close the debug view and the tabpage it owns.
function M.close_panels()
  require("dapui").close({})
  if debug_tab_valid() and #vim.api.nvim_list_tabpages() > 1 then
    -- Closing the last tabpage fails, which would leave the view half torn
    -- down; the panels are already gone, so stopping here is the right end.
    vim.cmd(vim.api.nvim_tabpage_get_number(debug_tab) .. "tabclose")
  end
  debug_tab = nil
end

function M.toggle_panels()
  if debug_tab_valid() then M.close_panels() else M.open_panels() end
end

---Place a stopped frame, for `dap.defaults.fallback.switchbuf`.
---
---nvim-dap's `uselast` sets the frame in the current window, or in the previous
---one when the current window holds no source. In a tabpage carrying six debug
---panels around one file window, "the previous window" is usually a panel, and
---the frame lands inside Scopes or the REPL. `ensure_editor_win` asks the
---question this actually needs -- a window a file can go into -- and creates one
---when the tabpage has none.
---
---Like `uselast`, and unlike `usetab`, it stays inside the current tabpage.
---That is what keeps stepping from the editor tab in the editor tab.
---@param bufnr integer
---@param line integer
---@param column integer
function M.jump(bufnr, line, column)
  local win = require("util.window").ensure_editor_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  local ok = pcall(vim.api.nvim_win_set_cursor, win, { line, math.max((column or 1) - 1, 0) })
  if not ok then
    vim.notify(
      ("Adapter reported a frame at %d:%d, outside the buffer"):format(line, column or 1),
      vim.log.levels.WARN)
    return
  end
  -- Matches nvim-dap's own jump: focus follows the frame unless you are typing
  -- in the REPL, and folds open so the line is actually on screen.
  if vim.bo[vim.api.nvim_get_current_buf()].filetype ~= "dap-repl" then
    vim.api.nvim_set_current_win(win)
  end
  vim.api.nvim_win_call(win, function() vim.cmd("normal! zv") end)
end

---The root of the session tree the current session belongs to.
---An adapter that owns several targets (js-debug driving a browser, Electron)
---answers `startDebugging` with child sessions, and `dap.session()` follows
---whichever child last stopped. Whole-session actions belong to the root:
---`Session:close()` does not cascade, and a child's config is an
---adapter-internal object rather than a launchable configuration.
local function root_session()
  local session = require("dap").session()
  while session and session.parent do session = session.parent end
  return session
end

---Attach configs from this filetype and the current project's launch.json.
function M.attach()
  local dap = require("dap")
  local bufnr, cwd = vim.api.nvim_get_current_buf(), vim.fn.getcwd()
  local ft = vim.bo[bufnr].filetype
  local configs = vim.list_extend({}, dap.configurations[ft] or {})
  local ok, project = pcall(require("dap.ext.vscode").getconfigs, cwd .. "/.vscode/launch.json")
  if ok then
    vim.list_extend(configs, project)
  else
    vim.notify("Cannot read launch.json: " .. tostring(project), vim.log.levels.WARN)
  end
  configs = vim.tbl_filter(function(config) return config.request == "attach" end, configs)
  if #configs == 0 then
    vim.notify("No attach configuration for " .. ft, vim.log.levels.INFO)
    return
  end
  vim.ui.select(configs, { prompt = "Attach to running target:", format_item = function(c) return c.name end },
    function(config)
      if not config then return end
      if vim.api.nvim_get_current_buf() ~= bufnr or vim.fn.getcwd() ~= cwd then
        vim.notify("Source context changed; reopen the attach picker", vim.log.levels.WARN)
        return
      end
      -- Attach is explicit even when another session is paused/running.
      dap.run(config, { new = true, filetype = ft })
    end)
end

function M.run_target(kind)
  local bufnr = vim.api.nvim_get_current_buf()
  local ft, path = vim.bo[bufnr].filetype, vim.api.nvim_buf_get_name(bufnr)
  local target = (M.targets[ft] or {})[kind]
  if vim.bo[bufnr].buftype ~= "" or path == "" or not target then
    vim.notify("No " .. kind .. " debug target for this buffer (" .. ft .. ")", vim.log.levels.WARN)
    return
  end
  local ok, err = pcall(vim.cmd.update)
  if not ok then
    vim.notify("Cannot save debug target: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if vim.api.nvim_get_current_buf() ~= bufnr or vim.api.nvim_buf_get_name(bufnr) ~= path then
    vim.notify("Save hooks changed the current file; retry the debug action", vim.log.levels.WARN)
    return
  end
  -- Save hooks may format the buffer. Capture its position after saving, then
  -- pass values rather than editor lookups to asynchronous language handlers.
  local cursor = vim.api.nvim_win_get_cursor(0)
  target({ bufnr = bufnr, path = path, filetype = ft, line = cursor[1], col = cursor[2] })
end

---Parse the source once for language-owned target queries; fail visibly.
function M.syntax(ctx)
  local ok, parser = pcall(vim.treesitter.get_parser, ctx.bufnr)
  if not ok or not parser then
    local lang = vim.treesitter.language.get_lang(ctx.filetype) or ctx.filetype
    vim.notify("Debug target discovery needs :TSInstall " .. lang, vim.log.levels.WARN)
    return
  end
  return parser:parse()[1]:root(), parser:lang()
end

---Return the live Visual selection (including line/block modes), or <cexpr>.
---Leave Visual mode before opening a prompt/panel; never touch a yank register.
function M.expression()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), {
      type = mode,
      exclusive = vim.o.selection == "exclusive",
    })
    vim.cmd("normal! " .. vim.keycode("<Esc>"))
    return table.concat(lines, "\n")
  end
  return vim.fn.expand("<cexpr>")
end

function M.evaluate()
  local expression = M.expression()
  if expression ~= "" then require("dap.ui.widgets").hover(expression) end
end

function M.watch()
  local expression = M.expression()
  vim.ui.input({ prompt = "Watch expression: ", default = expression }, function(value)
    if value and vim.trim(value) ~= "" then
      require("dapui").elements.watches.add(value)
    end
  end)
end

function M.logpoint()
  -- Blocking input keeps the source location stable while entering the message.
  local ok, message = pcall(vim.fn.input, "Log message (use {expression}): ")
  if ok and vim.trim(message) ~= "" then
    require("dap").set_breakpoint(nil, nil, message)
  end
end

function M.disconnect()
  local root = root_session()
  if not root then
    vim.notify("No active debug session", vim.log.levels.INFO)
    return
  end
  -- Disconnect every session in the tree, deepest first. Session:disconnect
  -- asks one session to let go, so disconnecting whichever session happens to
  -- be current leaves the rest of the tree attached to the target. The child
  -- list is snapshotted: a closing session removes itself from its parent.
  -- `before_disconnect` is an adapter option (go_remote sets one), so it is
  -- read per session rather than once for the tree.
  local function disconnect(session)
    for _, child in ipairs(vim.tbl_values(session.children)) do disconnect(child) end
    if session.closed then return end
    local before = (session.adapter.options or {}).before_disconnect
    if before then
      before(session, function()
        if not session.closed then session:disconnect({ terminateDebuggee = false }) end
      end)
    else
      session:disconnect({ terminateDebuggee = false })
    end
  end
  disconnect(root)
end

function M.restart()
  local dap = require("dap")
  local root = root_session()
  if not root then
    vim.notify("No active debug session", vim.log.levels.INFO)
    return
  end
  -- dap.restart() acts on dap.session(). Left on a child it restarts that one
  -- target, or -- with no restart request -- terminates the child and replays
  -- the child's config, which cannot be launched on its own. Select the root
  -- first; this is the same call the session picker behind `<leader>ds` makes.
  dap.set_session(root)
  dap.restart()
end

function M.exceptions()
  local dap = require("dap")
  local session = dap.session()
  if not session then
    vim.notify("Start a debug session before choosing exception breakpoints", vim.log.levels.INFO)
    return
  end
  local available = session.capabilities.exceptionBreakpointFilters or {}
  if #available == 0 then
    vim.notify("This adapter offers no exception breakpoint filters", vim.log.levels.INFO)
    return
  end
  local choices = { { label = "None", filters = {} }, { label = "All", filters = {} } }
  for _, filter in ipairs(available) do
    table.insert(choices[2].filters, filter.filter)
    table.insert(choices, { label = filter.label or filter.filter, filters = { filter.filter } })
  end
  vim.ui.select(choices, {
    prompt = "Break on exceptions:",
    format_item = function(item) return item.label end,
  }, function(choice)
    -- A picker may outlive its session. Never apply it to a different target.
    if choice and dap.session() == session then dap.set_exception_breakpoints(choice.filters) end
  end)
end

return M
