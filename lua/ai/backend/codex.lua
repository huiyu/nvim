local M = {}

local current

local function snacks()
  return _G.Snacks or require("snacks")
end

local function active()
  return current ~= nil and current:buf_valid()
end

local function project_root(path)
  local start = path ~= "" and path or (vim.uv.cwd() or vim.fn.getcwd())
  if path ~= "" then start = vim.fs.dirname(path) end
  return vim.fs.root(start, ".git") or vim.uv.cwd() or vim.fn.getcwd()
end

local function terminal_opts(root)
  return {
    cwd = root,
    auto_insert = true,
    start_insert = true,
    auto_close = true,
    win = {
      position = "right",
      width = 90,
      wo = { winfixwidth = true },
    },
  }
end

local function enter_insert(term)
  if not term or not term:buf_valid() then return end
  local win = term.win
  if
    not win
    or not vim.api.nvim_win_is_valid(win)
    or vim.api.nvim_win_get_buf(win) ~= term.buf
    or vim.bo[term.buf].buftype ~= "terminal"
  then
    return
  end

  vim.api.nvim_win_call(win, function() vim.cmd.startinsert() end)
end

local function start(args, root)
  current = snacks().terminal.open(args, terminal_opts(root))
  local term = current
  term:on("TermClose", function()
    if current == term then current = nil end
  end, { buf = true })
  enter_insert(term)
  return current
end

local function ensure()
  if active() then return current, false end
  local path = vim.api.nvim_buf_get_name(0)
  return start({ "codex" }, project_root(path)), true
end

local function show_and_focus(term)
  term:show()
  term:focus()
  enter_insert(term)
end

local function send(text, opts)
  opts = opts or {}
  local term, created = ensure()
  local delay = created and 350 or 0

  vim.defer_fn(function()
    if not term:buf_valid() then return end
    local channel = vim.bo[term.buf].channel
    if not channel or channel <= 0 then
      vim.notify("Codex terminal is not ready", vim.log.levels.WARN)
      return
    end

    show_and_focus(term)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\27", "")
    local payload
    if opts.raw then
      payload = text
    else
      payload = "\27[200~" .. text .. "\27[201~"
    end
    if opts.submit then payload = payload .. "\r" end
    vim.api.nvim_chan_send(channel, payload)
  end, delay)
end

local function buffer_context()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    vim.notify("Current buffer has no file path", vim.log.levels.WARN)
    return
  end

  local root = project_root(path)
  local rel = vim.fs.relpath(root, path) or path
  return buf, rel
end

function M.toggle()
  if active() then
    current:toggle()
    enter_insert(current)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  start({ "codex" }, project_root(path))
end

function M.focus()
  local term = ensure()
  show_and_focus(term)
end

function M.resume()
  if active() then
    show_and_focus(current)
    vim.notify("A Codex session is already active; exit it before resuming another", vim.log.levels.INFO)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  start({ "codex", "resume" }, project_root(path))
end

function M.continue()
  if active() then
    show_and_focus(current)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  start({ "codex", "resume", "--last" }, project_root(path))
end

function M.select_model()
  send("/model", { raw = true, submit = true })
end

function M.add_buffer()
  local buf, rel = buffer_context()
  if not buf then return end
  if vim.bo[buf].modified then
    vim.notify("Codex @-mentions read the saved file; this buffer has unsaved changes", vim.log.levels.WARN)
  end
  send("@" .. rel .. " ", { submit = false })
end

function M.send_selection()
  local buf = vim.api.nvim_get_current_buf()
  local anchor = vim.fn.getpos("v")
  local cursor = vim.fn.getpos(".")
  local visual_mode = vim.fn.mode()
  local ok, lines = pcall(vim.fn.getregion, anchor, cursor, { type = visual_mode })
  if not ok or not lines or #lines == 0 then
    vim.notify("Could not read the visual selection", vim.log.levels.WARN)
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)
  local root = project_root(path)
  local rel = path ~= "" and (vim.fs.relpath(root, path) or path) or "[unsaved buffer]"
  local first_line = math.min(anchor[2], cursor[2])
  local last_line = math.max(anchor[2], cursor[2])
  local draft

  if path ~= "" and not vim.bo[buf].modified then
    -- Codex CLI has file mentions but no editor selection attachment API. Keep
    -- the line range in the composer so the user can add an instruction first.
    draft = ("@%s lines %d-%d "):format(rel, first_line, last_line)
  else
    local filetype = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "text"
    draft = ("Selection from %s (lines %d-%d):\n````%s\n%s\n````\n")
      :format(rel, first_line, last_line, filetype, table.concat(lines, "\n"))

    if path ~= "" then
      vim.notify(
        "Buffer has unsaved changes; pasted the exact selection instead of a Codex @-mention",
        vim.log.levels.INFO
      )
    end
  end

  send(draft, { submit = false })
end

return M
