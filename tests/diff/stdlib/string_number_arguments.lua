-- expect: pass
-- stage: stdlib
-- feature: stdlib-string-coercion
-- normalize: none

-- Library functions taking strings accept numbers (luaL_checklstring) and
-- convert them with the same formatting as tostring.

print(string.len(12), string.len(1.5), string.len(-0.0), string.len(2^63))
print(string.rep(5, 2), string.rep(1.5, 2, 0), ("x"):rep(2), string.rep("a", 3, 7))
print(string.upper(12), string.lower(1e100), string.reverse(123), string.sub(12345, 2, 3), string.byte(65))
print(string.find(123, 2), string.match(1.25, "%.(%d+)"))
print(string.gsub(1234, 2, 9))
print(string.gsub("abc", "b", 1.5))
print(string.gsub("abc", "%w", "%0%0", 1.0))

local pieces = {}
for piece in string.gmatch(12321, 2) do pieces[#pieces + 1] = piece end
print(#pieces)

print(string.format("%s %s %d %5.1s|", 1, 2.5, 3, 1e15))
print(string.format("%s|%s", setmetatable({}, {__tostring = function() return 2.5 end}), 1e15))
print(table.concat({1, 2.5, "x", 1e15, -0.0}, 3), table.concat({}, 1), table.concat({1, 2}, 0.5))
print(utf8.len(123), utf8.codepoint(7), utf8.offset(123, 2))
print(string.char(65, "66", 67.0), select("#", string.byte("abc", "1", "3.0")))
print(string.pack("i4", 3):len(), string.unpack("i4", string.pack("i4", 7)))
print(math.floor("3.7"), math.abs("-3"), math.tointeger("8"), math.tointeger(2^53))
print(select(2.0, "a", "b"), string.byte("abc", 1.0, 2.0), string.sub("abc", "2"))
io.write(1e15, " ", 2^63, " ", 0.1, " ", 12, " ", -0.0, "\n")
