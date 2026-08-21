-- Turns a provider-neutral entry list into buffer lines plus fold levels.
--
-- This module never learns which provider produced the entries; that knowledge
-- stops at the adapters.

local M = {}

-- Fold levels are returned as an array parallel to the lines, never written into
-- the text as `{{{` / `}}}` markers. Markers would travel with every yank out of
-- the transcript and land in whatever the user pasted them into.
local VISIBLE = 0
local FOLDED = 1

local function speaker(entry, label)
  if entry.role == "user" then return "You" end
  return label or "Assistant"
end

---Build the buffer contents for a session.
---@param entries ai.transcript.Entry[]
---@param meta { provider: string, label: string?, id: string?, root: string?, title: string?, truncated: boolean?, dropped: integer? }
---@return string[] lines
---@return integer[] folds parallel fold level per line
function M.build(entries, meta)
  local lines, folds = {}, {}

  local function emit(text, level)
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
      lines[#lines + 1] = line
      folds[#folds + 1] = level
    end
  end

  local turns = 0
  for _, entry in ipairs(entries) do
    if entry.kind == "text" then turns = turns + 1 end
  end

  emit(("# %s · %s%s"):format(
    meta.label or meta.provider,
    meta.id or "session",
    meta.title and (" · " .. meta.title) or ""
  ), VISIBLE)
  emit(("> %s · %d turns"):format(meta.root or "", turns), VISIBLE)

  if meta.truncated then
    emit(("> **Truncated**: %s older entries were dropped to keep this responsive.")
      :format(meta.dropped and tostring(meta.dropped) or "some"), VISIBLE)
  end

  if #entries == 0 then
    emit("", VISIBLE)
    emit("*This session has no readable entries yet.*", VISIBLE)
    return lines, folds
  end

  -- One heading per speaker change keeps `]]` / `[[` navigation meaningful; a
  -- heading per entry would put one between a tool call and its result.
  local previous_role
  for _, entry in ipairs(entries) do
    if entry.role ~= previous_role then
      previous_role = entry.role
      emit("", VISIBLE)
      -- The heading stays visible even when everything under it folds; a folded
      -- heading would make a tool-only turn vanish entirely.
      emit(("## ▌ %s%s"):format(
        speaker(entry, meta.label),
        entry.time and (" · " .. entry.time) or ""
      ), VISIBLE)
    end

    -- The separator stays visible even before a folded entry. Two reasons: it
    -- breaks consecutive tool calls into one fold each instead of merging a
    -- whole run into a single opaque block, and it keeps the fold starting on
    -- the "▸ Bash" header rather than on a blank line -- 'foldtext' shows the
    -- fold's first line, and "+-- 45 lines:" followed by nothing is useless.
    emit("", VISIBLE)

    if entry.kind == "text" then
      emit(entry.text, VISIBLE)
    elseif entry.kind == "thinking" then
      emit("▸ thinking", FOLDED)
      emit("", FOLDED)
      emit(entry.text, FOLDED)
    else
      -- A result knows its tool only when the call/result ids correlated;
      -- without a name "▸ result" reads better than "▸ tool result".
      local header
      if entry.kind == "tool_call" then
        header = ("▸ %s"):format(entry.name or "tool")
      elseif entry.name then
        header = ("▸ %s result"):format(entry.name)
      else
        header = "▸ result"
      end
      emit(header, FOLDED)
      emit("", FOLDED)
      -- Fenced so a tool payload containing markdown cannot restyle the page.
      emit("```", FOLDED)
      emit(entry.text, FOLDED)
      emit("```", FOLDED)
    end
  end

  return lines, folds
end

---'foldexpr' callback. Reads the level table the viewer attached to the buffer.
---@return integer
function M.foldexpr()
  local levels = vim.b.ai_transcript_folds
  if type(levels) ~= "table" then return 0 end
  return levels[vim.v.lnum] or 0
end

return M
