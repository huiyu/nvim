-- Read-only viewer for the active provider's recorded sessions.
--
-- Scrolling an agent TUI is not Vim: no `/` search history, no text objects, no
-- yanking into the editor's registers. This renders the session into an ordinary
-- buffer so all of that just works.
--
-- The source is the CLI's own JSONL transcript rather than the terminal.
-- Claude runs on the alternate screen, so its tmux wrapper keeps no scrollback
-- at all (measured `alt=1 hist=0/2000`); reading from disk is the only source
-- that works for both providers, and it leaves the wrapper untouched.

---@class ai.transcript.Session
---@field id string        short identifier shown in the picker
---@field path string      absolute path to the JSONL file
---@field mtime integer    sort key, newest first
---@field title string|nil Claude exposes ai-title records; Codex has none

---@class ai.transcript.Entry
---@field role "user"|"assistant"
---@field kind "text"|"thinking"|"tool_call"|"tool_result"
---@field text string
---@field name string|nil  tool name, for tool_call / tool_result
---@field time string|nil  local "HH:MM", for the turn heading

---@class ai.transcript.Adapter
---@field sessions fun(root: string): ai.transcript.Session[]
---@field parse fun(path: string, cap: integer): ai.transcript.Entry[], boolean

local config = require("ai.config")
local render = require("ai.transcript.render")

local M = {}

-- Safety valve, not a feature. This project's largest transcript is ~530
-- entries; the cap exists so a pathological file from elsewhere cannot stall the
-- editor. Measured: a 270 MB transcript costs 349 ms and a 244 MB Lua heap when
-- fully retained, versus 68 ms and 21 MB streamed into a bounded ring.
local ENTRY_CAP = 5000

-- Indirection so tests can substitute an adapter, and so provider knowledge
-- stops here. Mirrors how lua/ai/init.lua resolves backends.
M._adapter = function()
  return require("ai.transcript." .. config.provider)
end

local function open_window(buf)
  vim.cmd("tabnew")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  return win
end

local function apply(buf, session, entries, truncated)
  local lines, folds = render.build(entries, {
    provider = config.provider,
    label = config.label,
    id = session.id,
    title = session.title,
    root = config.project_root(""),
    truncated = truncated,
    dropped = truncated and ENTRY_CAP or nil,
  })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  -- Attach the fold table before 'foldmethod' is evaluated, or the first fold
  -- pass sees nothing and every line collapses to level 0.
  vim.b[buf].ai_transcript_folds = folds
end

local function configure(buf, session)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  -- A dedicated filetype rather than `markdown`. The markdown filetype drags in
  -- its ftplugin, any markdown LSP, conform's prettier rule, and Treesitter's
  -- own folding -- and that last one would fight the foldexpr below. Start the
  -- markdown parser explicitly to borrow the highlighting without the rest.
  vim.bo[buf].filetype = "ai-transcript"
  pcall(vim.treesitter.start, buf, "markdown")

  vim.b[buf].ai_transcript_path = session.path
  vim.b[buf].ai_transcript_session = session

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc, silent = true, nowait = true })
  end

  -- Single letters are the convention for standalone panels in this config; the
  -- viewer owns its window and no file.
  map("R", function() M.refresh(buf) end, "Refresh transcript")
  map("q", function()
    -- Close only this window. Never touch buffers the viewer does not own.
    if #vim.api.nvim_tabpage_list_wins(0) > 1 then
      vim.api.nvim_win_close(0, false)
    else
      vim.cmd("bwipeout")
    end
  end, "Close transcript")
end

local function configure_window(win)
  vim.wo[win].foldmethod = "expr"
  vim.wo[win].foldexpr = "v:lua.require'ai.transcript.render'.foldexpr()"
  vim.wo[win].foldlevel = 0
  vim.wo[win].foldenable = true
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
end

---Render one session into a fresh read-only buffer.
---@param session ai.transcript.Session
local function show(session)
  local adapter = M._adapter()
  local entries, truncated = adapter.parse(session.path, ENTRY_CAP)

  local buf = vim.api.nvim_create_buf(false, true)
  configure(buf, session)
  apply(buf, session, entries, truncated)

  local win = open_window(buf)
  configure_window(win)

  -- The newest turn is the entry point; searching backward with `?` is the
  -- intended motion from there.
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
end

---Open the most recent session for the current project.
function M.open_current()
  local root = config.project_root("")
  local sessions = M._adapter().sessions(root)
  if #sessions == 0 then
    vim.notify(
      ("No %s transcript found for %s"):format(config.label, root),
      vim.log.levels.WARN
    )
    return
  end
  show(sessions[1])
end

---Pick from this project's recorded sessions.
function M.pick()
  local root = config.project_root("")
  local sessions = M._adapter().sessions(root)
  if #sessions == 0 then
    vim.notify(
      ("No %s transcript found for %s"):format(config.label, root),
      vim.log.levels.WARN
    )
    return
  end

  local items = {}
  for index, session in ipairs(sessions) do
    items[#items + 1] = {
      idx = index,
      session = session,
      text = ("%s  %s"):format(
        os.date("%Y-%m-%d %H:%M", session.mtime),
        session.title or session.id
      ),
      file = session.path,
    }
  end

  Snacks.picker.pick({
    source = "ai_transcripts",
    items = items,
    format = "text",
    title = config.label .. " sessions",
    preview = "none",
    confirm = function(picker, item)
      picker:close()
      if item and item.session then show(item.session) end
    end,
  })
end

---Re-read the transcript backing `buf` and re-render it in place.
---@param buf integer
function M.refresh(buf)
  local session = vim.b[buf].ai_transcript_session
  if not session then return end

  local view = vim.fn.winsaveview()
  local entries, truncated = M._adapter().parse(session.path, ENTRY_CAP)
  apply(buf, session, entries, truncated)
  vim.fn.winrestview(view)
end

return M
