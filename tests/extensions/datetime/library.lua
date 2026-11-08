local keys = {}
for key in pairs(datetime) do keys[#keys + 1] = key end
table.sort(keys)
print(table.concat(keys, " "))

local d = datetime.parse("1979-05-27T07:32:00.5-07:00")
print(d, d:kind(), d.year, d.offset, d:unix())
print(d:utc(), d:at_offset(330), d:with{ hour = 9 }, d:date(), d:time())
print(d:format("%A %d %B %Y %H:%M:%S.%f %z"), datetime.unix(0):format("%c %Z"), d:format())

local day = datetime.new{ year = 2026, month = 11, day = 7, isdst = false }
print(day, day:kind(), day:weekday(), day:yday())
print(datetime.new{ hour = 23, min = 59 }:kind(), datetime.parse("1979-05-27T07:32"):kind())
print(datetime.unix(0), datetime.unix(1.25), datetime.unix(10, 5))

print(d:add{ months = 1, days = 3, hours = -2 }, d:add{ weeks = 1, minutes = 30, seconds = 1, nanoseconds = 500000000 })
print(datetime.parse("2024-01-31"):add{ months = 1 }, datetime.parse("2023-01-31"):add{ months = 1 }, datetime.parse("2024-02-29"):add{ years = 1 })
print(datetime.parse("23:30:00"):add{ hours = 2 }, datetime.parse("2024-03-01"):add{ days = -1 })

print(datetime.parse("1979-05-27T07:32:00-07:00") == datetime.parse("1979-05-27T14:32:00Z"))
print(datetime.parse("1979-05-27") == datetime.parse("1979-05-27"), datetime.parse("1979-05-27") == datetime.parse("1979-05-27T00:00:00"))
print(datetime.unix(0) < d, d <= d, d - datetime.unix(0), datetime.parse("10:00") - datetime.parse("09:30"))

for _, attempt in ipairs({
  function() return datetime.parse("1979-05-27") < datetime.parse("10:00:00") end,
  function() return d - 5 end,
  function() return d:add{ day = 1 } end,
  function() return d:add{ days = 1.5 } end,
  function() return datetime.parse("1979-05-27"):add{ hours = 1 } end,
  function() return datetime.parse("10:00:00"):add{ months = 1 } end,
  function() return datetime.parse("10:00:00"):format("%Y") end,
  function() return datetime.parse("1979-05-27T07:32"):unix() end,
  function() return datetime.parse("1979-05-27T25:00") end,
  function() return datetime.new{ month = 1 } end,
  function() return datetime.unix(1e300) end,
}) do
  print(select(2, pcall(attempt)))
end

local config = toml.read("deadline = 2026-11-07T17:00:00-08:00")
config.deadline = config.deadline:add{ days = 7 }
print(toml.write(config), json.write(config))
