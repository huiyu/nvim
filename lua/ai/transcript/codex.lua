-- Reads Codex's on-disk transcripts.
--
-- Codex could in principle be read from its tmux pane -- it runs with
-- --no-alt-screen and a 50000-line history -- but Claude cannot, so both
-- providers use the recorded transcript and the viewer stays provider-neutral.
--
-- The format is an undocumented implementation detail of a tool that ships
-- often, so every unrecognised record is skipped rather than raising. A schema
-- change should degrade to missing entries, never to a broken viewer.

local hhmm = require("ai.transcript.time").hhmm

local M = {}

local ROOT = vim.fn.expand("~/.codex/sessions")

---@param root string project root directory
---@return ai.transcript.Session[]
function M.sessions(root)
  -- Sessions are filed by date, not by project, so the owning directory is only
  -- discoverable from inside each file. Reading line 1 of every session is
  -- cheap enough to do eagerly: measured at 19 ms for 194 files.
  local sessions = {}
  for _, path in ipairs(vim.fn.globpath(ROOT, "**/*.jsonl", false, true)) do
    local stat = vim.uv.fs_stat(path)
    local handle = stat and io.open(path, "r")
    if handle then
      local first = handle:read("l")
      handle:close()
      if first then
        local ok, record = pcall(vim.json.decode, first)
        if
          ok
          and type(record) == "table"
          and type(record.payload) == "table"
          and record.payload.cwd == root
        then
          sessions[#sessions + 1] = {
            id = tostring(record.payload.id or vim.fn.fnamemodify(path, ":t:r")):sub(1, 8),
            path = path,
            mtime = stat.mtime.sec,
          }
        end
      end
    end
  end
  table.sort(sessions, function(a, b) return a.mtime > b.mtime end)
  return sessions
end

local function text_of(blocks)
  if type(blocks) ~= "table" then return "" end
  local parts = {}
  for _, block in ipairs(blocks) do
    -- `encrypted_content` blocks are opaque by design; skip rather than dump
    -- an unreadable blob into the transcript.
    if type(block) == "table" and type(block.text) == "string" then
      parts[#parts + 1] = block.text
    end
  end
  return table.concat(parts, "\n")
end

local function entry_from(payload, time)
  local kind = payload.type

  if kind == "message" then
    local role = payload.role
    -- `developer` carries injected instructions, not conversation.
    if role ~= "user" and role ~= "assistant" then return nil end
    local text = text_of(payload.content)
    if vim.trim(text) == "" then return nil end
    return { role = role, kind = "text", text = text, time = time }
  elseif kind == "reasoning" then
    -- In practice `summary` is empty and the real reasoning lives in
    -- `encrypted_content`, which cannot be read -- measured 58/58 empty in a
    -- real session. The schema does allow a populated summary, so render it
    -- when present and skip the record when not. Unlike Claude, Codex
    -- transcripts will usually show no thinking at all.
    local text = text_of(payload.summary)
    if vim.trim(text) == "" then return nil end
    return { role = "assistant", kind = "thinking", text = text, time = time }
  elseif kind == "custom_tool_call" then
    local input = payload.input
    if type(input) ~= "string" then input = vim.inspect(input or {}) end
    return {
      role = "assistant",
      kind = "tool_call",
      name = payload.name or "tool",
      text = input,
      time = time,
    }
  elseif kind == "custom_tool_call_output" then
    return {
      role = "assistant",
      kind = "tool_result",
      name = "result",
      text = text_of(payload.output),
      time = time,
    }
  end

  -- `agent_message` deliberately falls through. It carries sub-agent
  -- orchestration ("Message Type: NEW_TASK / Sender: /root"), not conversation.
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

  for line in handle:lines() do
    if line ~= "" then
      local decoded_ok, record = pcall(vim.json.decode, line)
      -- A partial trailing line is normal while the agent is still writing.
      if
        decoded_ok
        and type(record) == "table"
        and record.type == "response_item"
        and type(record.payload) == "table"
      then
        local entry = entry_from(record.payload, hhmm(record.timestamp))
        if entry then
          count = count + 1
          ring[(count - 1) % cap + 1] = entry
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
