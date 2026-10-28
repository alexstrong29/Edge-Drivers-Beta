-- Night / day tariff periods worked out from UTC epoch seconds.
-- The hub clock is UTC and Edge drivers can't see the location time zone,
-- so local time is computed here with plain arithmetic (no os.date / os.time(table),
-- which depend on the hub's process time zone).

local tariff = {}

-- days since 1970-01-01 for a civil date (Howard Hinnant's algorithm)
local function days_from_civil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

-- civil date for days since 1970-01-01
local function civil_from_days(z)
  z = z + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  if m <= 2 then y = y + 1 end
  return y, m, d
end

-- days since epoch of the last Sunday of a month
local function last_sunday(y, m)
  local next_y, next_m = y, m + 1
  if next_m > 12 then next_y, next_m = y + 1, 1 end
  local last = days_from_civil(next_y, next_m, 1) - 1
  local wday = (last + 4) % 7 -- 0 = Sunday (1970-01-01 was a Thursday)
  return last - wday
end

-- UK: BST (UTC+1) from 01:00 UTC on the last Sunday of March
-- until 01:00 UTC on the last Sunday of October, otherwise GMT
function tariff.uk_offset(utc)
  local y = civil_from_days(utc // 86400)
  local bst_start = last_sunday(y, 3) * 86400 + 3600
  local bst_end = last_sunday(y, 10) * 86400 + 3600
  if utc >= bst_start and utc < bst_end then return 3600 end
  return 0
end

-- zone: "uk" (GMT/BST automatic) or "utc" (no clock change)
function tariff.local_time(utc, zone)
  local offset = 0
  if zone ~= "utc" then offset = tariff.uk_offset(utc) end
  local t = utc + offset
  local days = t // 86400
  return days, (t % 86400) // 60 -- local day number, minutes since local midnight
end

-- local calendar keys for day / month / year totals, e.g. "2026-10-28", "2026-10", "2026"
function tariff.local_keys(utc, zone)
  local y, m, d = civil_from_days((tariff.local_time(utc, zone)))
  return {
    day = string.format("%04d-%02d-%02d", y, m, d),
    month = string.format("%04d-%02d", y, m),
    year = string.format("%04d", y),
  }
end

-- "HH:MM" -> minutes since midnight, or nil if invalid
function tariff.parse_hhmm(s)
  local h, m = tostring(s or ""):match("^%s*(%d%d?):(%d%d)%s*$")
  h, m = tonumber(h), tonumber(m)
  if not h or h > 23 or m > 59 then return nil end
  return h * 60 + m
end

-- Which period "utc" falls in, and an id unique to that occurrence of it
-- (period kind + local date it started), so a change of id means a new period.
-- The night window may cross midnight (e.g. 23:30-05:30).
function tariff.period(utc, zone, start_min, end_min)
  local days, mins = tariff.local_time(utc, zone)
  local kind, boundary
  local in_night
  if start_min <= end_min then
    in_night = mins >= start_min and mins < end_min
  else
    in_night = mins >= start_min or mins < end_min
  end
  if in_night then kind, boundary = "night", start_min else kind, boundary = "day", end_min end
  local start_day = mins >= boundary and days or days - 1
  local y, m, d = civil_from_days(start_day)
  return kind, string.format("%s:%04d-%02d-%02d", kind, y, m, d), mins
end

return tariff
