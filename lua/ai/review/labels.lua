-- Labels for baselines in the <leader>g pickers (<leader>gM, <leader>gk) and
-- for the views they open:
--
--   a round   picker  "<session>: <Source> <start> - <end>"
--             view    "<session>: <Source> <start>"
--   saved     both    "<name>: Saved <time>"
--
-- A round's session is its Conversation trailer, and its name and turns come
-- from the agent's own records (ai.transcript.marks). The name is the first
-- one the session had, so a later /rename or a renamed Codex thread leaves
-- it alone. The start is the baseline's time, taken as the prompt left; the
-- end is when the session's last turn ended before its next round began.
-- Both are compared to the millisecond (util.baseline.time_of): a prompt sent
-- in the same second as a turn ended must not take that turn's end.
--
-- "…" says the session is at work on this round: it was prompted after its
-- last turn ended -- by this round's own prompt, or by a later one this Nvim
-- heard that kept the round (nothing had changed) -- and it is alive, running
-- in this Nvim or writing its records in the last LIVE_SECONDS. A manual
-- round is no prompt, and a session killed mid-turn writes no end, so neither
-- shows "…" by itself. Without the records -- another machine, a deleted
-- transcript, a chat, a manual round with no owner -- a round shows its start
-- alone, and without a name no "<session>: ".
--
-- A label describes; it changes nothing about what a view compares. A round
-- against the working tree shows everything since its start, which is why a
-- view is labelled with the start alone.
--
-- The vcs layer gets these through describe() and never reads a trailer.
local M = {}

-- Names wider than this are cut, so the times after them stay in a 100-column
-- picker.
M.NAME_WIDTH = 40
-- How long describe() waits for the records before labelling with what it
-- has. A record read in the meantime is kept, for the next picker.
M.BUDGET_MS = 300
-- A session whose records were written this recently counts as alive, though
-- no terminal of this Nvim runs it (another Nvim, a restart).
M.LIVE_SECONDS = 30 * 60

local function same_day(a, b)
  return os.date("%Y-%m-%d", a) == os.date("%Y-%m-%d", b)
end

local function same_year(a, b)
  return os.date("%Y", a) == os.date("%Y", b)
end

-- A time with its date: "11-09 21:43", or with the year when it is not this one.
local function dated(t, now)
  return os.date(same_year(t, now) and "%m-%d %H:%M" or "%Y-%m-%d %H:%M", t) --[[@as string]]
end

---When `t` was, as a picker shows it: "11:16:38" today, "11-09 21:43" earlier
---this year, "2025-12-31 23:50" before.
---@param t number epoch seconds
---@param now? integer
---@return string
function M.stamp(t, now)
  now = now or os.time()
  t = math.floor(t)
  if same_day(t, now) then return os.date("%H:%M:%S", t) --[[@as string]] end
  return dated(t, now)
end

---From `start` to `ended`: "11:16:38 - 11:43:18" today, "11-09 21:43 - 22:13"
---on another day, both dated across midnight; "11:39:25 - …" while `open`;
---the start alone when the end is unknown.
---@param start number
---@param ended? number
---@param open? boolean
---@param now? integer
---@return string
function M.span(start, ended, open, now)
  now = now or os.time()
  start = math.floor(start)
  if open then return M.stamp(start, now) .. " - …" end
  if not ended then return M.stamp(start, now) end
  ended = math.floor(ended)
  if same_day(start, ended) then
    local fmt = same_day(start, now) and "%H:%M:%S" or "%H:%M"
    return M.stamp(start, now) .. " - " .. os.date(fmt, ended)
  end
  return dated(start, now) .. " - " .. dated(ended, now)
end

---`name` on one line, cut to `width` display columns with "…".
---@param name string
---@param width? integer
---@return string
function M.shorten(name, width)
  width = width or M.NAME_WIDTH
  name = vim.trim((name:gsub("%c+", " "):gsub("  +", " ")))
  if vim.fn.strdisplaywidth(name) <= width then return name end
  local out, used = {}, 0
  for i = 0, vim.fn.strchars(name) - 1 do
    local ch = vim.fn.strcharpart(name, i, 1)
    local w = vim.fn.strdisplaywidth(ch)
    if used + w > width - 1 then break end
    out[#out + 1], used = ch, used + w
  end
  return table.concat(out) .. "…"
end

local function rounds()
  local ok, mod = pcall(require, "ai.review.rounds")
  return ok and type(mod) == "table" and mod or {}
end

local function trailers(entry)
  return type(entry.trailers) == "table" and entry.trailers or {}
end

-- "claude:<id>" -> "claude", "<id>"; nil for anything else.
local function native_session(conversation)
  if type(conversation) ~= "string" then return nil end
  local agent, id = conversation:match("^(%l+):(.+)$")
  if agent == "claude" or agent == "codex" then return agent, id end
end

-- When baseline `e` was taken, to the millisecond.
local function start_of(e)
  local ok, base = pcall(require, "util.baseline")
  if ok and type(base.time_of) == "function" then
    local got, t = pcall(base.time_of, e)
    if got and type(t) == "number" then return t end
  end
  return e.time
end

-- What the records say about round `e`: { name?, ended?, open? }. `marks` is
-- conversation -> { title?, ends, turns, mtime? }; `mod` is ai.review.rounds.
local function round_info(e, entries, marks, mod, now)
  local t = trailers(e)
  local conversation = t.Conversation
  local m = conversation and marks[conversation]
  if not m then return {} end
  local info = { name = m.title }
  if not m.turns then return info end
  local start = start_of(e)
  -- The session's next round, if it has one here.
  local next_start
  for _, o in ipairs(entries) do
    if o ~= e and o.kind == "round" and trailers(o).Conversation == conversation then
      local s = start_of(o)
      if s > start or (s == start and tostring(o.id) > tostring(e.id)) then
        next_start = next_start and math.min(next_start, s) or s
      end
    end
  end
  for _, ended in ipairs(m.ends) do
    if ended >= start and (not next_start or ended < next_start) then info.ended = ended end
  end
  if next_start then return info end
  -- At work: prompted after the session's last end -- this round's own prompt
  -- (a round of the agent itself; a Late one may have been taken after the
  -- turn it belongs to ended) or a later one heard here -- and alive.
  local agent = native_session(conversation)
  local prompted = t.Source == agent and t.Late ~= "1" and start or nil
  local asked = type(mod.prompted_at) == "function" and mod.prompted_at(conversation) or nil
  if type(asked) == "number" and asked > (prompted or -math.huge) then prompted = asked end
  local last_end = m.ends[#m.ends]
  if prompted and (not last_end or prompted > last_end) then
    local running = type(mod.running) == "function" and mod.running(conversation) == true
    info.open = running or (m.mtime ~= nil and now - m.mtime <= M.LIVE_SECONDS)
  end
  return info
end

-- { label, display } for one entry, or nil to keep the caller's own.
local function build(e, entries, marks, mod, now)
  local t = trailers(e)
  if e.kind == "saved" then
    local name = t.Label or (type(e.subject) == "string" and (e.subject:match("^saved · (.+)$") or e.subject)) or ""
    local label = ("%s: Saved %s"):format(M.shorten(name), M.stamp(e.time, now))
    return { label = label, display = label }
  end
  if e.kind ~= "round" or type(mod.source_label) ~= "function" then return nil end
  local source = mod.source_label(t.Source)
  if not source then return nil end
  local info = round_info(e, entries, marks, mod, now)
  local prefix = info.name and info.name ~= "" and (M.shorten(info.name) .. ": ") or ""
  return {
    label = ("%s%s %s"):format(prefix, source, M.stamp(e.time, now)),
    display = ("%s%s %s"):format(prefix, source, M.span(e.time, info.ended, info.open, now)),
  }
end

---Labels for util.baseline.list entries: `cb(labels)`, labels[i] = { label,
---display } for entries[i] -- the view's label and the picker's line -- or nil
---where the caller keeps its own (a round with no Source, an unknown kind).
---Waits for the sessions' records up to `opts.budget_ms` (BUDGET_MS); a
---session not read by then is labelled without them. Always called back on
---the main loop, once.
---@param entries baseline.Entry[]
---@param cb fun(labels: ({ label: string, display: string }|nil)[])
---@param opts? { budget_ms?: integer, now?: integer }
function M.describe(entries, cb, opts)
  opts = opts or {}
  local now = opts.now or os.time()
  local wanted, seen = {}, {}
  for _, e in ipairs(entries) do
    local conversation = e.kind == "round" and trailers(e).Conversation or nil
    local agent, id = native_session(conversation)
    if agent and id and conversation and not seen[conversation] then
      seen[conversation] = true
      wanted[#wanted + 1] = { conversation = conversation, agent = agent, id = id }
    end
  end
  -- conversation -> the full marks; and its name from a read for the name
  -- alone, which skips files holding none (a long Codex rollout), so a name is
  -- there even when the turns miss the budget.
  local marks, names, finished = {}, {}, false
  local function finish()
    if finished then return end
    finished = true
    local mod = rounds()
    local merged = {}
    for conversation, name in pairs(names) do merged[conversation] = { title = name, ends = {}, turns = false } end
    for conversation, m in pairs(marks) do merged[conversation] = m end
    local out = {}
    for i, e in ipairs(entries) do
      local ok, item = pcall(build, e, entries, merged, mod, now)
      out[i] = ok and item or nil
    end
    cb(out)
  end
  if #wanted == 0 then return vim.schedule(finish) end
  local pending = 2 * #wanted
  local function landed()
    pending = pending - 1
    if pending == 0 then finish() end
  end
  local reader = require("ai.transcript.marks")
  for _, w in ipairs(wanted) do
    reader.read(w.agent, w.id, function(m)
      if m and m.title then names[w.conversation] = m.title end
      landed()
    end, { titles = true })
    reader.read(w.agent, w.id, function(m)
      marks[w.conversation] = m
      landed()
    end)
  end
  vim.defer_fn(finish, opts.budget_ms or M.BUDGET_MS)
end

---The name of the session working in `root` -- the chat on the right first,
---as ai.review.rounds lists them, then the agent terminals by name -- for
---<leader>gK to offer:
---`cb(name)`, or `cb(nil)` when no agent terminal there has reported its
---session, it has no name yet, or the records take longer than
---`opts.budget_ms`. Loads nothing when no agent terminal was ever opened.
---@param root string
---@param cb fun(name: string|nil)
---@param opts? { budget_ms?: integer }
function M.current_name(root, cb, opts)
  opts = opts or {}
  local done = false
  local function finish(name)
    if done then return end
    done = true
    cb(name)
  end
  local mod = package.loaded["ai.review.rounds"]
  local live = {}
  if type(mod) == "table" and type(mod.live_conversations) == "function" then
    local ok, got = pcall(mod.live_conversations, root)
    if ok and type(got) == "table" then live = got end
  end
  local agent, id
  for _, item in ipairs(live) do
    if item.kind == "native" then
      agent, id = native_session(item.conversation)
      if agent then break end
    end
  end
  if not (agent and id) then return vim.schedule(function() finish(nil) end) end
  require("ai.transcript.marks").read(agent, id, function(m)
    local name = m and m.title and vim.trim((m.title:gsub("%c+", " ")))
    finish(name ~= "" and name or nil)
  end, { titles = true })
  vim.defer_fn(function() finish(nil) end, opts.budget_ms or M.BUDGET_MS)
end

return M
