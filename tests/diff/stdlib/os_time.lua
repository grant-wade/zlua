-- expect: pass
-- stage: stdlib
-- feature: system-libraries
-- normalize: none

-- UTC formats use conversions that every Lua build accepts; local-time checks
-- only compare round trips so the host time zone does not matter.
local stamps = { 0, 86399, 951782400, 1700000000, 1709251199, 4102444799 }
for _, t in ipairs(stamps) do
  print(t, os.date("!%Y-%m-%d %H:%M:%S %a %A %b %B %d %H %I %j %m %M %p %S %U %w %W %y %Y %%", t))
  local d = os.date("!*t", t)
  print(d.year, d.month, d.day, d.hour, d.min, d.sec, d.wday, d.yday, d.isdst)
  print(os.time(os.date("*t", t)) == t, os.date("*t", t).isdst == os.date("*t", t).isdst)
end

local t = { year = 2000, month = 14, day = 35, hour = 12, min = 70, sec = -5 }
os.time(t)
print(t.year, t.month, t.day, t.hour, t.min, t.sec, t.wday, t.yday)
print(os.time({ year = 2024, month = 1, day = 16, hour = 12 }) - os.time({ year = 2024, month = 1, day = 15, hour = 12 }))
print(os.time({ year = 2024, month = 1, day = 15 }) == os.time({ year = 2024, month = 1, day = 15, hour = 12 }))

print(pcall(os.time, { year = 2000 }))
print(pcall(os.time, { year = 2000, month = "x", day = 1 }))
print(pcall(os.time, { year = 2000, month = 1, day = 2 ^ 40 }))
print(pcall(os.time, 1))
print(pcall(os.date, "%Ez"))
print(pcall(os.date, "!%Y", 1.5))

print(math.type(os.time()), type(os.clock()), os.clock() >= 0)
print(os.difftime(10, 3), os.difftime(2 ^ 31, 0))
