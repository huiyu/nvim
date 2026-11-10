-- Reads Codex's on-disk transcripts.
--
-- Codex could in principle be read from its tmux pane -- it runs with
-- --no-alt-screen and a 50000-line history -- but Claude cannot, so both
-- providers use the recorded transcript and the viewer stays provider-neutral.
--
-- The format is an undocumented implementation detail of a tool that ships
-- often, so every unrecognised record is skipped rather than raising. A schema
-- change should degrade to missing entries, never to a broken viewer.

local time_util = require("ai.transcript.time")
local hhmm = time_util.hhmm

local M = {}

-- $CODEX_HOME, as the CLI reads it, else ~/.codex. Looked up on every call,
-- so a changed environment (or a spec's fixture directory) is followed.
local function home()
  local dir = vim.env.CODEX_HOME
  if dir == nil or dir == "" then dir = vim.fn.expand("~/.codex") end
  return dir
end

---@param root string project root directory
---@return ai.transcript.Session[]
function M.sessions(root)
  -- Sessions are filed by date, not by project, so the owning directory is only
  -- discoverable from inside each file. Reading line 1 of every session is
  -- cheap enough to do eagerly: measured at 19 ms for 194 files.
  local sessions = {}
  for _, path in ipairs(vim.fn.globpath(home() .. "/sessions", "**/*.jsonl", false, true)) do
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

---------------------------------------------------------------------------
-- Session marks (ai.transcript.marks): what review labels read
---------------------------------------------------------------------------

-- A turn's end in the rollout: completed, or stopped by Esc.
M.ROLLOUT_PATTERNS = { '"type":"task_complete"', '"type":"turn_aborted"' }
-- Every session_index.jsonl record names its thread.
M.INDEX_PATTERNS = { '"thread_name"' }

---What a rollout record says about its session: `{ ended }` (epoch seconds)
---for a turn that completed or was aborted, nil for anything else.
---@param record any decoded JSON
---@return { ended: number }|nil
function M.mark(record)
  if type(record) ~= "table" or record.type ~= "event_msg" or type(record.payload) ~= "table" then return nil end
  local kind = record.payload.type
  if kind ~= "task_complete" and kind ~= "turn_aborted" then return nil end
  local ended = time_util.epoch(record.timestamp)
  return ended and { ended = ended } or nil
end

---What a session_index.jsonl record says: `{ id, title }`, the thread's name
---at that point. A renamed thread gets another record further down.
---@param record any decoded JSON
---@return { id: string, title: string }|nil
function M.index_mark(record)
  if type(record) ~= "table" or type(record.id) ~= "string" or type(record.thread_name) ~= "string" then
    return nil
  end
  return { id = record.id, title = record.thread_name }
end

-- id -> { path, compressed } found before, or { at = os.time() } of a miss.
local found = {}
-- A miss is looked for again after this long: the session may be on its way.
M.MISS_TTL = 60

-- The local dates a rollout of thread `id` may be filed under. Codex thread ids
-- are UUIDv7, whose first 48 bits are the creation time in milliseconds, and a
-- rollout is filed by the local date it started; the day on either side covers
-- a clock or zone change.
local function days_of(id)
  local high, low = id:match("^(%x%x%x%x%x%x%x%x)%-(%x%x%x%x)%-7%x%x%x%-")
  if not high then return {} end
  local sec = math.floor(tonumber(high .. low, 16) / 1000)
  return { os.date("%Y/%m/%d", sec), os.date("%Y/%m/%d", sec - 86400), os.date("%Y/%m/%d", sec + 86400) }
end

-- The rollout of thread `id`: `path, compressed`, or nil. A cold rollout is
-- compressed in place, rollout-*-<id>.jsonl.zst, until Codex resumes it.
-- Remembered, and checked with one stat; the whole tree is globbed only when
-- the thread's own day directories do not hold it.
local function rollout(id)
  local hit = found[id]
  if hit and hit.path and vim.uv.fs_stat(hit.path) then return hit.path, hit.compressed end
  if hit and hit.at and os.time() - hit.at < M.MISS_TTL then return nil end
  local sessions = home() .. "/sessions"
  local function look(dir_glob)
    for _, ext in ipairs({ ".jsonl", ".jsonl.zst" }) do
      local path = vim.fn.globpath(sessions, dir_glob .. "/rollout-*-" .. id .. ext, false, true)[1]
      if path then return path, ext == ".jsonl.zst" end
    end
  end
  local path, compressed
  for _, day in ipairs(days_of(id)) do
    path, compressed = look(day)
    if path then break end
  end
  if not path then path, compressed = look("*/*/*") end
  found[id] = path and { path = path, compressed = compressed } or { at = os.time() }
  return path, compressed
end

---The files that hold session `id`'s marks: the thread index (its name) and
---its rollout (its turns). Either may be missing. A compressed rollout is read
---through `zstd -dc` when zstd is installed, and not at all otherwise.
---@param id string
---@return ai.transcript.MarkSource[]
function M.sources(id)
  if type(id) ~= "string" or not id:match("^[%w-]+$") then return {} end
  local out = {}
  local index = home() .. "/session_index.jsonl"
  if vim.uv.fs_stat(index) then
    out[#out + 1] = { path = index, patterns = M.INDEX_PATTERNS, mark = M.index_mark, turns = false }
  end
  local path, compressed = rollout(id)
  if path and compressed and vim.fn.executable("zstd") == 1 then
    out[#out + 1] = {
      path = path, patterns = M.ROLLOUT_PATTERNS, mark = M.mark, titles = false,
      decompress = "zstd -dc -- " .. vim.fn.shellescape(path),
    }
  elseif path and not compressed then
    out[#out + 1] = { path = path, patterns = M.ROLLOUT_PATTERNS, mark = M.mark, titles = false }
  end
  return out
end

---For the spec: forget where rollouts were found.
function M._forget()
  found = {}
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

---@param tool_names table<string, string> call_id -> tool name, filled as calls are seen
local function entry_from(payload, time, tool_names)
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
    local name = payload.name or "tool"
    if payload.call_id then tool_names[payload.call_id] = name end
    return {
      role = "assistant",
      kind = "tool_call",
      name = name,
      text = input,
      time = time,
    }
  elseif kind == "custom_tool_call_output" then
    return {
      role = "assistant",
      kind = "tool_result",
      name = payload.call_id and tool_names[payload.call_id] or nil,
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

  -- A call always precedes its output, so a forward-filled map is enough to
  -- label a result with the tool that produced it.
  local tool_names = {}

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
        local entry = entry_from(record.payload, hhmm(record.timestamp), tool_names)
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
