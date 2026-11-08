local function hex(bytes)
  return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local extension = msgpack.read("\xd4\x01\x7f")
print(extension.type, hex(extension.data), tostring(extension):match("^%a+"))
print(hex(msgpack.write(msgpack.extension(5, "abc"))))
print(select(2, pcall(msgpack.extension, -1, "")))
print(select(2, pcall(json.write, extension)))

for _, text in ipairs({ "1970-01-01T00:00:00Z", "2018-01-02T03:04:05.678901234Z", "2514-05-30T01:53:04Z", "1969-12-31T23:59:59Z" }) do
  local bytes = msgpack.write(datetime.parse(text))
  print(text, hex(bytes), tostring(msgpack.read(bytes)) == text)
end
print(tostring(msgpack.read(msgpack.write(datetime.parse("2000-01-01T09:00:00+09:00")))))
print(select(2, pcall(msgpack.write, datetime.parse("2000-01-01T09:00:00"))))

print(hex(msgpack.write(1.5)), hex(msgpack.write(0.1)), hex(msgpack.write(1 / 0)))
