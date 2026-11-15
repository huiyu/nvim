-- Turns the current visual selection into text an agent can consume.
--
-- Codex receives a file/range reference or the exact unsaved text;
-- CodeCompanion adds the captured lines as a fenced block. Capture happens
-- before any asynchronous question, while the live Visual selection exists.
--
-- Nothing here notifies. The caller owns how a failure or a fallback is shown,
-- because <leader>as and <leader>ai surface them differently.

local cwd = require("agent_workbench.context")

local M = {}

---Build an agent-ready draft from the live visual selection.
---Must be called while Visual mode is active -- it reads `mode()` and the `v`
---mark, not the `'<`/`'>` marks left behind afterwards.
---@return string|nil draft   nil when the selection could not be read
---@return string|nil err     reason, set only when draft is nil
---@return string|nil notice  informational message the caller may surface
function M.draft()
  local buf = vim.api.nvim_get_current_buf()
  local anchor = vim.fn.getpos("v")
  local cursor = vim.fn.getpos(".")
  local visual_mode = vim.fn.mode()

  -- Guard explicitly rather than relying on getregion() to object. Outside
  -- Visual mode it does not fail: the `v` mark still holds a stale position, so
  -- it happily returns the current line and the caller would seed a draft the
  -- user never selected.
  local kind = visual_mode:sub(1, 1)
  if not (kind == "v" or kind == "V" or kind == "\22" or kind == "s" or kind == "S" or kind == "\19") then
    return nil, "No visual selection is active"
  end

  local ok, lines = pcall(vim.fn.getregion, anchor, cursor, { type = visual_mode })
  if not ok or not lines or #lines == 0 then
    return nil, "Could not read the visual selection"
  end

  local path = vim.api.nvim_buf_get_name(buf)
  local root = cwd.project_root(path)
  local rel = path ~= "" and (vim.fs.relpath(root, path) or path) or "[unsaved buffer]"

  -- The selection can be made in either direction, so the anchor is not
  -- necessarily the first line.
  local first_line = math.min(anchor[2], cursor[2])
  local last_line = math.max(anchor[2], cursor[2])

  if path ~= "" and not vim.bo[buf].modified then
    -- The recipient is not known yet and may run in another project. Keep
    -- the absolute path, with a trailing space ready for the next instruction.
    return ("@%s lines %d-%d "):format(path, first_line, last_line)
  end

  -- An unsaved or modified buffer cannot be referenced by path -- the agent
  -- would read stale bytes -- so send the exact selection instead.
  local filetype = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "text"
  local draft = ("Selection from %s (lines %d-%d):\n````%s\n%s\n````\n")
    :format(rel, first_line, last_line, filetype, table.concat(lines, "\n"))

  local notice
  if path ~= "" then
    notice = "Buffer has unsaved changes; pasted the exact selection instead of a file mention"
  end

  return draft, nil, notice
end

-- A directory listing contains names rather than selected source code.
-- Oil is the only listing here; its selections are refused by the facade.
local TREE_FILETYPES = { oil = true }

---A selection taken whole, before anything asks where it goes.
---
---vim.ui.select is asynchronous: by the time its choice arrives Visual mode is
---long gone and the current buffer may be another one, so every route a
---selection can take is computed here, from plain Neovim API, while it is
---live. CodeCompanion's utils.context.get is no substitute afterwards: it
---reads the current buffer's '< and '> marks and another buffer's lines.
---@class ai.Capture
---@field buf integer
---@field win integer
---@field mode string "v", "V" or "\22"
---@field l1 integer first line, 1-based
---@field l2 integer last line
---@field lines string[] exactly the selected text, columns and blocks kept
---@field path string the buffer's name, "" for none
---@field modified boolean the buffer has unsaved changes: a file mention would miss them
---@field filetype string
---@field tree boolean a directory listing, refused as source context
---@field draft? string captured file/range reference or text for a terminal agent
---@field err? string why there is no draft
---@field notice? string what the draft had to fall back to

---Capture the live Visual selection and leave Visual mode, '< and '> set.
---@return ai.Capture|nil capture
---@return string|nil err
function M.capture()
  local mode = vim.fn.mode():sub(1, 1)
  local visual = ({ v = "v", V = "V", ["\22"] = "\22", s = "v", S = "V", ["\19"] = "\22" })[mode]
  if not visual then return nil, "No visual selection is active" end
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local anchor, cursor = vim.fn.getpos("v"), vim.fn.getpos(".")
  local ok, lines = pcall(vim.fn.getregion, anchor, cursor, { type = visual })
  local draft, err, notice = M.draft()
  vim.cmd("normal! \27")
  if not ok or type(lines) ~= "table" or #lines == 0 then return nil, "Could not read the visual selection" end
  return {
    buf = buf, win = win, mode = visual,
    l1 = math.min(anchor[2], cursor[2]), l2 = math.max(anchor[2], cursor[2]),
    lines = lines, path = vim.api.nvim_buf_get_name(buf), modified = vim.bo[buf].modified,
    filetype = vim.bo[buf].filetype,
    tree = TREE_FILETYPES[vim.bo[buf].filetype] == true,
    draft = draft, err = err, notice = notice,
  }
end

---Is the current buffer a directory listing (see ai.Capture.tree)?
---@param buf integer?
---@return boolean
function M.is_tree(buf)
  return TREE_FILETYPES[vim.bo[buf or 0].filetype] == true
end

return M
