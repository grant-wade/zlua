-- expect: pass
-- stage: stdlib
-- feature: stdlib-string
-- normalize: none

print(string.len("abc"), string.byte("abc", 2), string.char(65, 66, 67))
print(string.sub("abcdef", 2, -2), string.reverse("abc"))
print(string.lower("AbC"), string.upper("AbC"), string.rep("ha", 3, ":"))
print(string.find("abc123def", "%d+"))
print(string.match("abc123def", "%d+"))
print(string.match("aaab", ".+b"), string.match("b", ".+b") == nil)
print(string.match("um caracter ? extra", "[^%sa-z]"), string.match("]]]ab", "[^]]+"))
print(string.gsub("a1b22", "%d+", "#"))
print(string.gsub("abc", ".", "%0?"))
print(string.format("%s:%d:%x", "n", 42, 255))

local out = {}
for value in string.gmatch("a1 b22 c333", "%d+") do
  table.insert(out, value)
end
print(table.concat(out, ","))

local packed = string.pack("<i4I2", -2, 258)
print(#packed)
print(string.unpack("<i4I2", packed))
print(string.packsize("<i4I2"))

-- packsize checks length arithmetic without allocating enormous strings.
local size_limit = string.packsize('T') == 4 and 0xffffffff or math.maxinteger
local halves = 'c' .. (size_limit // 2) .. 'c' .. (size_limit // 2)
assert(string.packsize(halves) == size_limit - 1)
assert(string.packsize(halves .. 'x') == size_limit)
assert(not pcall(string.packsize, halves .. 'xx'))
assert(not pcall(string.packsize, 'c' .. size_limit .. '0'))
