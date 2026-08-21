-- Turns the current visual selection into text an agent can consume.
--
-- This lives outside the backends because the two providers attach selections
-- through different channels. Codex has no editor-selection API, so its
-- <leader>as pastes text. Claude's <leader>as goes over the IDE WebSocket
-- (:ClaudeCodeSend) and produces no text at all. <leader>ai needs text under
-- both providers to seed the agent's input box, so the text form has exactly one
-- producer: this module.
--
-- Nothing here notifies. The caller owns how a failure or a fallback is shown,
-- because <leader>as and <leader>ai surface them differently.

local config = require("ai.config")

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
  local root = config.project_root(path)
  local rel = path ~= "" and (vim.fs.relpath(root, path) or path) or "[unsaved buffer]"

  -- The selection can be made in either direction, so the anchor is not
  -- necessarily the first line.
  local first_line = math.min(anchor[2], cursor[2])
  local last_line = math.max(anchor[2], cursor[2])

  if path ~= "" and not vim.bo[buf].modified then
    -- A saved file can be referenced instead of pasted. The trailing space is
    -- load-bearing: it leaves the cursor ready for an instruction after the
    -- mention rather than glued to it.
    return ("@%s lines %d-%d "):format(rel, first_line, last_line)
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

return M
