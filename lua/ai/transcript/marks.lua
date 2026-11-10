-- Session marks: a session's name and the times its turns ended, read from the
-- agents' own records. Which files and which records is provider knowledge, in
-- ai.transcript.claude and ai.transcript.codex (`sources(id)`, `mark(record)`);
-- this module only reads. ai.review.labels is its user.
--
-- The records are large -- 85 MB for a long Claude session here, 476 MB for a
-- Codex one -- and only a few of their lines matter, so:
--
--   * a line is decoded only when it contains one of the adapter's plain
--     substrings, found with string.find over CHUNK-sized blocks;
--   * the reading runs on libuv's thread pool, SLICE bytes per job, so the
--     editor never waits for it and quitting waits for one slice at most;
--   * a file is read once: the offset read up to is kept, and the next call
--     reads only what was appended since. A file that shrank or was replaced
--     -- another inode, or other first bytes, since a new file can reuse a
--     freed inode -- is read again from the start;
--   * each worker thread keeps its own Lua state between jobs and nothing
--     collects it while it is idle, so a job collects its garbage after every
--     block: without that, one 476 MB rollout left about 280 MB resident.
--
-- A compressed source (`decompress`, a shell command reading the file to
-- stdout) is a cold file -- Codex compresses a rollout it has not touched for
-- days -- so it is read whole, in one job, and again only if it changes.
--
-- A line longer than MAX_LINE is skipped whole -- no mark is that long, and a
-- multi-megabyte tool result is not worth holding. A session's name is the
-- first title it ever had: a later one (/rename, a renamed Codex thread) is
-- read and ignored.

---@class ai.transcript.MarkSource
---@field path string
---@field patterns string[] plain substrings; a line holding none is never decoded
---@field mark fun(record: any): { title?: string, id?: string, ended?: number }|nil
---@field turns? boolean false: the file records no turns (a name index), so reading it says nothing about them
---@field titles? boolean false: the file holds no names (a rollout), so a read for the name skips it
---@field decompress? string shell command that writes the file's text to stdout (paths escaped)

---@class ai.transcript.Marks
---@field title? string the session's first name
---@field ends number[] epoch seconds of every turn end, ascending
---@field turns boolean a source of turn ends was read (an empty `ends` is then real)
---@field mtime? integer when the newest of its turn files was last written

local M = {}

local uv = vim.uv

M.MAX_LINE = 1048576
M.SLICE = 64 * 1048576
M.CHUNK = 4 * 1048576

-- path -> { ino, head, size, mtime, offset, skipping, titles, ends, gen,
--           running, ready, failed, waiting, patterns, mark, decompress }
local cache = {}
local exiting = false
local work
-- Jobs queued so far, for the spec.
M._jobs = 0

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("ai_transcript_marks", { clear = true }),
  callback = function() exiting = true end,
})

-- Runs on the thread pool, so it has no upvalues and uses no vim.*: libuv
-- hands it a fresh Lua state, kept for that thread's later jobs. Reads `path`
-- from `offset` -- or the stdout of `command` from its start, whole, when one
-- is given -- `chunk_size` bytes at a time, for about `budget` bytes. Returns
-- the path, the offset of the first byte not consumed (a trailing partial line
-- is left for the next read), whether a too-long line is still being skipped
-- there, the hit lines in file order joined by "\n", whether the end was
-- reached, an error, and `gen` back.
local function scan(path, offset, skipping, patterns, max_line, budget, chunk_size, gen, command)
  local ok, consumed, still_skipping, hits, eof = pcall(function()
    local pats = {}
    for pat in patterns:gmatch("[^\1]+") do pats[#pats + 1] = pat end
    local fd
    if command ~= "" then
      fd = assert(io.popen(command, "r"))
      budget = math.huge
    else
      fd = assert(io.open(path, "rb"))
      fd:seek("set", offset)
    end
    local out, carry, base, read, at_end = {}, "", offset, 0, false
    while read < budget do
      local chunk = fd:read(chunk_size)
      if not chunk then
        at_end = true
        break
      end
      read = read + #chunk
      local data = carry .. chunk
      chunk = nil
      local back = data:reverse():find("\n", 1, true)
      if not back then
        if skipping or #data > max_line then
          skipping, carry, base = true, "", base + #data
        else
          carry = data
        end
      else
        local last = #data - back + 1
        local first = 1
        if skipping then
          first = data:find("\n", 1, true) + 1
          skipping = false
        end
        local found, starts = {}, {}
        for _, pat in ipairs(pats) do
          local pos = first
          while true do
            local s = data:find(pat, pos, true)
            if not s or s > last then break end
            local ls = s
            while ls > first and data:byte(ls - 1) ~= 10 do ls = ls - 1 end
            local le = data:find("\n", s, true)
            if not found[ls] and le - ls <= max_line then
              found[ls] = data:sub(ls, le - 1)
              starts[#starts + 1] = ls
            end
            pos = le + 1
          end
        end
        table.sort(starts)
        for _, ls in ipairs(starts) do out[#out + 1] = found[ls] end
        carry = data:sub(last + 1)
        base = base + last
        if #carry > max_line then skipping, base, carry = true, base + #carry, "" end
      end
      data = nil
      collectgarbage("collect")
    end
    fd:close()
    return base, skipping, table.concat(out, "\n"), at_end
  end)
  collectgarbage("collect")
  if not ok then return path, offset, skipping, "", false, tostring(consumed), gen end
  return path, consumed, still_skipping, hits, eof, nil, gen
end

local function deliver(cb, ...)
  local args = { n = select("#", ...), ... }
  vim.schedule(function() cb(unpack(args, 1, args.n)) end)
end

-- The name `st` holds for session `id`: the file's own (a transcript), or the
-- one an index gives that id.
local function title_in(st, id)
  return st.titles[id] or st.titles[""]
end

-- Hand `st` to the waiting callbacks: all of them, or (`names_only`) those
-- that want a name alone and whose name is now known.
local function flush(st, names_only)
  local keep = {}
  for _, w in ipairs(st.waiting) do
    if names_only and not (w.name_of and title_in(st, w.name_of)) then
      keep[#keep + 1] = w
    else
      deliver(w.cb, st)
    end
  end
  st.waiting = keep
end

local start

---@param path string
local function landed(path, consumed, skipping, hits, eof, err, gen)
  local st = cache[path]
  if not st then return end
  st.running = false
  -- The file was replaced while this slice ran: start over for the new one.
  if st.gen ~= gen then return start(path, st) end
  if err then
    st.failed = err
    return flush(st)
  end
  for line in hits:gmatch("[^\n]+") do
    local ok, record = pcall(vim.json.decode, line)
    local got, m
    if ok then got, m = pcall(st.mark, record) end
    if got and type(m) == "table" then
      if type(m.title) == "string" and m.title ~= "" then
        local key = type(m.id) == "string" and m.id or ""
        if st.titles[key] == nil then st.titles[key] = m.title end
      end
      if type(m.ended) == "number" then st.ends[#st.ends + 1] = m.ended end
    end
  end
  -- A compressed file is read whole; it counts as read up to its size.
  local progressed = consumed > st.offset
  st.offset, st.skipping = st.decompress and st.size or consumed, skipping
  if next(st.titles) ~= nil then flush(st, true) end
  -- Another slice only if this one got somewhere: a slice is longer than any
  -- line kept, so it always does, and this keeps it from spinning if not.
  if not eof and progressed and not exiting then return start(path, st) end
  table.sort(st.ends)
  st.ready = eof
  flush(st)
end

start = function(path, st)
  if exiting then return flush(st) end
  st.running = true
  M._jobs = M._jobs + 1
  local ok, err = pcall(function()
    work = work or uv.new_work(scan, function(...)
      local args = { n = select("#", ...), ... }
      vim.schedule(function() landed(unpack(args, 1, args.n)) end)
    end)
    local from = st.decompress and 0 or st.offset
    work:queue(path, from, st.skipping, table.concat(st.patterns, "\1"), M.MAX_LINE, M.SLICE, M.CHUNK, st.gen,
      st.decompress or "")
  end)
  if not ok then
    st.running, st.failed = false, tostring(err)
    flush(st)
  end
end

local HEAD = 64

-- The first HEAD bytes of `path`, "" when it cannot be read.
local function head(path)
  local fd = uv.fs_open(path, "r", 0)
  if not fd then return "" end
  local data = uv.fs_read(fd, HEAD, 0)
  uv.fs_close(fd)
  return data or ""
end

-- One file's first bytes then and now: the same file, if one starts the other
-- (it may have been shorter than HEAD the first time).
local function same_start(a, b)
  local n = math.min(#a, #b)
  return a:sub(1, n) == b:sub(1, n)
end

-- Bring `src.path` up to date, then `cb(state)`; `cb(nil)` when it is gone.
-- `name_of` (a session id): only that session's name is wanted, so answer as
-- soon as it is known.
---@param src ai.transcript.MarkSource
local function read_path(src, cb, name_of)
  local stat = uv.fs_stat(src.path)
  if not stat then
    cache[src.path] = nil
    return deliver(cb, nil)
  end
  local st = cache[src.path]
  local first = head(src.path)
  local changed = st and (st.ino ~= stat.ino or stat.size < st.offset or not same_start(st.head, first)
    or (src.decompress ~= nil and stat.size ~= st.size))
  if not st or changed then
    st = {
      ino = stat.ino, head = first, offset = 0, skipping = false, titles = {}, ends = {},
      gen = st and st.gen + 1 or 1, running = st and st.running or false,
      waiting = st and st.waiting or {}, patterns = src.patterns, mark = src.mark, decompress = src.decompress,
    }
    cache[src.path] = st
  end
  if #first > #st.head then st.head = first end
  st.size, st.mtime = stat.size, stat.mtime.sec
  st.failed = nil
  if name_of and title_in(st, name_of) then return deliver(cb, st) end
  if not st.running and st.ready and stat.size == st.offset then return deliver(cb, st) end
  st.waiting[#st.waiting + 1] = { cb = cb, name_of = name_of }
  if not st.running then start(src.path, st) end
end

---The marks of session `id` of `agent` ("claude" or "codex"): `cb(marks)` once
---every record file of it was read to its end, or `cb(nil)` when they say
---nothing of it (no such session here, a format this does not know). With
---`opts.titles` only the name is wanted: files holding no names are not read,
---and a file holding one answers as soon as it is found. Always called back
---on the main loop, once, never before this returns.
---@param agent string
---@param id string
---@param cb fun(marks: ai.transcript.Marks|nil)
---@param opts? { titles?: boolean }
function M.read(agent, id, cb, opts)
  local titles = type(opts) == "table" and opts.titles == true
  local ok, adapter = pcall(require, "ai.transcript." .. tostring(agent))
  local sources = {}
  if ok and type(adapter) == "table" and type(adapter.sources) == "function" then
    local got, list = pcall(adapter.sources, id)
    if got and type(list) == "table" then sources = list end
  end
  if titles then sources = vim.tbl_filter(function(src) return src.titles ~= false end, sources) end
  if #sources == 0 then return deliver(cb, nil) end
  local states, pending = {}, #sources
  for i, src in ipairs(sources) do
    read_path(src, function(st)
      states[i] = st
      pending = pending - 1
      if pending > 0 then return end
      local out = { ends = {}, turns = false }
      for j, s in pairs(states) do
        if s and not s.failed then
          out.title = out.title or title_in(s, id)
          if s.ready and not titles then
            vim.list_extend(out.ends, s.ends)
            -- A source whose records end turns: the transcript or the rollout.
            if sources[j].turns ~= false then
              out.turns = true
              out.mtime = math.max(out.mtime or 0, s.mtime or 0)
            end
          end
        end
      end
      table.sort(out.ends)
      cb((out.title or out.turns) and out or nil)
    end, titles and id or nil)
  end
end

---For the spec: forget every file read so far.
function M._reset()
  cache = {}
  exiting = false
end

---For the spec: what is known about `path`.
function M._state(path)
  return cache[path]
end

return M
