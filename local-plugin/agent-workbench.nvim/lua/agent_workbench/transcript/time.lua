-- Timestamp rendering shared by the transcript adapters.
--
-- Both CLIs record ISO 8601 in UTC. Showing that verbatim would put every turn
-- hours away from when the user remembers it happening, so it is converted to
-- local time.

local M = {}

-- Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant's
-- days_from_civil). Pure arithmetic: os.time() reads its table as local time,
-- and correcting that with today's UTC offset is wrong for any timestamp on
-- the other side of a daylight-saving change.
local function days_from_civil(y, m, d)
  local floor = math.floor
  y = m <= 2 and y - 1 or y
  local era = floor((y >= 0 and y or y - 399) / 400)
  local yoe = y - era * 400
  local doy = floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

---Seconds since the epoch of an ISO 8601 timestamp ("2026-11-10T03:43:18.085Z",
---"...+08:00", or with no zone, read as UTC), fractions kept; nil for anything
---else.
---@param timestamp any
---@return number|nil
function M.epoch(timestamp)
  if type(timestamp) ~= "string" then return nil end
  local y, mo, d, h, mi, s, rest = timestamp:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
  if not y then return nil end
  local frac, zone = rest:match("^(%.%d+)(.*)$")
  if not frac then frac, zone = "", rest end
  local offset = 0
  if zone ~= "" and zone ~= "Z" then
    local sign, zh, zm = zone:match("^([+-])(%d%d):?(%d%d)$")
    if not sign then return nil end
    offset = (tonumber(zh) * 3600 + tonumber(zm) * 60) * (sign == "-" and -1 or 1)
  end
  local days = days_from_civil(tonumber(y), tonumber(mo), tonumber(d))
  local secs = days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s) - offset
  return frac ~= "" and secs + tonumber("0" .. frac) or secs
end

---Render an ISO 8601 UTC timestamp as local "HH:MM".
---@param timestamp any
---@return string|nil
function M.hhmm(timestamp)
  local epoch = M.epoch(timestamp)
  if not epoch then return nil end
  return os.date("%H:%M", math.floor(epoch)) --[[@as string]]
end

return M
