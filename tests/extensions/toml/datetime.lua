local value = toml.read([[
offset = 1979-05-27T07:32:00.5-07:00
local_datetime = 1979-05-27 07:32
local_date = 1979-05-27
local_time = 07:32:00.999999999
]])
for _, key in ipairs({ "offset", "local_datetime", "local_date", "local_time" }) do
  local d = value[key]
  print(key, tostring(d), d.year, d.month, d.day, d.hour, d.min, d.sec, d.nsec, d.offset)
end
print(toml.write(value, { layout = "sections" }))
print(json.write({ when = value.local_date }), csv.write({ { when = value.offset } }, { record_terminator = "lf" }))

print(datetime.unix(0), datetime.unix(1.5), datetime.new({ hour = 23, min = 59 }))
print(datetime.new({ year = 2024, month = 2, day = 29, hour = 0, min = 0, sec = 0, offset = 330, isdst = false }))

for _, bad in ipairs({ "1979-13-01", "1979-05-27T25:00:00", "07:32:00Z", "1979-05-27T07:32:00+24:00", "" }) do
  print(select(2, pcall(datetime.parse, bad)))
end
print(select(2, pcall(datetime.new, { year = 2023, month = 2, day = 29 })))
print(select(2, pcall(datetime.new, { hour = 1, min = 0, offset = 60 })))

local edited = datetime.parse("2000-01-01")
edited.month = 13
print(select(2, pcall(toml.write, { edited = edited })))
