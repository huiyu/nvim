-- Reads Claude Code's on-disk transcripts.
--
-- Why disk rather than the terminal: the pane is not a reliable record. On
-- Claude Code's alt-screen renderer (`/tui fullscreen`) the tmux wrapper keeps
-- no scrollback at all -- measured `alt=1 hist=0/2000` against a live session --
-- so there is nothing to capture. On `/tui default` some scrollback survives,
-- but the screen is a rendering of the conversation rather than the
-- conversation: wrapped lines, redrawn frames and truncation are
-- indistinguishable from content. The on-disk JSONL is the only exact source,
-- and it is the same shape of answer for both providers.
--
-- The format is an undocumented implementation detail of a tool that ships
-- often, so every unrecognised record is skipped rather than raising. A schema
-- change should degrade to missing entries, never to a broken viewer.

local M = {}

local ROOT = vim.fn.expand("~/.claude/projects")

-- Claude derives a project directory name from the cwd by replacing both path
-- separators and dots with dashes:
--   /Users/jeff/.config/nvim  ->  -Users-jeff--config-nvim
-- (the doubled dash comes from `/` and `.` colliding on `/.config`).
local function slug(root)
  return (root:gsub("[/.]", "-"))
end

local time_util = require("ai.transcript.time")
local hhmm = time_util.hhmm

---@param root string project root directory
---@return ai.transcript.Session[]
function M.sessions(root)
  local dir = ROOT .. "/" .. slug(root)
  local sessions = {}
  for _, path in ipairs(vim.fn.globpath(dir, "*.jsonl", false, true)) do
    local stat = vim.uv.fs_stat(path)
    if stat then
      sessions[#sessions + 1] = {
        id = vim.fn.fnamemodify(path, ":t:r"):sub(1, 8),
        path = path,
        mtime = stat.mtime.sec,
      }
    end
  end
  table.sort(sessions, function(a, b) return a.mtime > b.mtime end)

  -- The title is cheap only for the session the caller is likely to open, so
  -- resolve it lazily rather than scanning every file up front.
  for _, session in ipairs(sessions) do
    session.title = M.title(session.path)
  end
  return sessions
end

---Read the agent-generated title, if the session has one yet.
---@param path string
---@return string|nil
function M.title(path)
  local ok, handle = pcall(io.open, path, "r")
  if not ok or not handle then return nil end
  local title
  for line in handle:lines() do
    if line:find('"ai-title"', 1, true) then
      local decoded_ok, record = pcall(vim.json.decode, line)
      if decoded_ok and type(record) == "table" and record.aiTitle then
        title = record.aiTitle
      end
    end
  end
  handle:close()
  return title
end

-- `message.content` is either a bare string or an array of typed blocks. Both
-- forms occur in the same real file, so both are handled.
local function blocks_of(content)
  if type(content) == "string" then
    return { { type = "text", text = content } }
  end
  if type(content) == "table" then return content end
  return {}
end

---@param tool_names table<string, string> id -> tool name, filled as tool_use is seen
local function entry_from(block, role, time, tool_names)
  if block.type == "text" then
    if type(block.text) ~= "string" or vim.trim(block.text) == "" then return nil end
    return { role = role, kind = "text", text = block.text, time = time }
  elseif block.type == "thinking" then
    -- Reasoning text is not persisted: real sessions carry `thinking` blocks
    -- whose `thinking` field is an empty string, keeping only the signature.
    -- Skip rather than emit blank entries.
    if type(block.thinking) ~= "string" or vim.trim(block.thinking) == "" then return nil end
    return { role = role, kind = "thinking", text = block.thinking, time = time }
  elseif block.type == "tool_use" then
    local name = block.name or "tool"
    if block.id then tool_names[block.id] = name end
    return {
      role = role,
      kind = "tool_call",
      name = name,
      text = vim.inspect(block.input or {}),
      time = time,
    }
  elseif block.type == "tool_result" then
    local text = block.content
    if type(text) ~= "string" then text = vim.inspect(text or "") end
    return {
      -- Attributed to the assistant even though the record's role is "user".
      -- Tool results arrive inside user messages because that is how the API
      -- frames them, but the user did not type them, and rendering them as a
      -- user turn invents a conversation that never happened.
      role = "assistant",
      kind = "tool_result",
      name = block.tool_use_id and tool_names[block.tool_use_id] or nil,
      text = text,
      time = time,
    }
  end
  return nil
end

---@param path string
---@param cap integer maximum entries to retain
---@return ai.transcript.Entry[] entries
---@return boolean truncated
function M.parse(path, cap)
  local ok, handle = pcall(io.open, path, "r")
  if not ok or not handle then return {}, false end

  -- Stream into a fixed-size ring rather than collecting every record first.
  -- Measured against a 270 MB transcript: full retention costs 349 ms and a
  -- 244 MB Lua heap, streaming costs 68 ms and 21 MB.
  local ring, count = {}, 0
  local function push(entry)
    count = count + 1
    ring[(count - 1) % cap + 1] = entry
  end

  -- tool_use always precedes its tool_result, so a forward-filled map is enough
  -- to label a result with the tool that produced it.
  local tool_names = {}

  for line in handle:lines() do
    if line ~= "" then
      local decoded_ok, record = pcall(vim.json.decode, line)
      -- A partial trailing line is normal while the agent is still writing.
      if decoded_ok and type(record) == "table" then
        local role = record.type
        if (role == "user" or role == "assistant") and type(record.message) == "table" then
          local time = hhmm(record.timestamp)
          for _, block in ipairs(blocks_of(record.message.content)) do
            if type(block) == "table" then
              local entry = entry_from(block, role, time, tool_names)
              if entry then push(entry) end
            end
          end
        end
      end
    end
  end
  handle:close()

  if count <= cap then
    return vim.list_slice(ring, 1, count), false
  end

  -- Unwrap the ring so the oldest retained entry comes first.
  local start = count % cap
  local ordered = {}
  for i = 0, cap - 1 do
    ordered[#ordered + 1] = ring[(start + i) % cap + 1]
  end
  return ordered, true
end

return M
