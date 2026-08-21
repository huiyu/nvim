-- Timestamp rendering shared by the transcript adapters.
--
-- Both CLIs record ISO 8601 in UTC. Showing that verbatim would put every turn
-- hours away from when the user remembers it happening, so it is converted to
-- local time.

local M = {}

-- os.time() interprets its table as *local* time, but these components are UTC,
-- so the naive result is off by exactly the local UTC offset. Read that offset
-- from strftime's %z ("+0800") rather than round-tripping through os.date table
-- form, which is both fiddlier and harder to type-check.
local function utc_offset()
  local zone = os.date("%z") --[[@as string]]
  local sign, hours, minutes = zone:match("([+-])(%d%d)(%d%d)")
  if not sign then return 0 end
  local seconds = tonumber(hours) * 3600 + tonumber(minutes) * 60
  return sign == "-" and -seconds or seconds
end

---Render an ISO 8601 UTC timestamp as local "HH:MM".
---@param timestamp any
---@return string|nil
function M.hhmm(timestamp)
  if type(timestamp) ~= "string" then return nil end

  local year, month, day, hour, minute, second =
    timestamp:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then return nil end

  local epoch = os.time({
    year = tonumber(year) or 1970,
    month = tonumber(month) or 1,
    day = tonumber(day) or 1,
    hour = tonumber(hour) or 0,
    min = tonumber(minute) or 0,
    sec = tonumber(second) or 0,
    isdst = false,
  })
  if not epoch then return nil end

  return os.date("%H:%M", epoch + utc_offset()) --[[@as string]]
end

return M
