-- expect: pass
-- stage: stdlib
-- feature: stdlib-table
-- normalize: none

-- table.unpack accepts any value: it takes the length and indexes it like
-- luaL_len and lua_geti, so errors come from those operations.

local function try(...)
  local r = table.pack(pcall(table.unpack, ...))
  for i = 1, r.n do r[i] = tostring(r[i]) end
  print(table.concat(r, ", ", 1, r.n))
end

try("abc")
try("abc", 1, 3)
try("abc", 2)
try("abc", 1, 0)
try(nil)
try(nil, 1, 2)
try(nil, 2, 1)
try(42)
try(42, 1, 1)
try(true)
try(true, 1, 0)
try()
try({}, "x")
try(nil, "x")
try("abc", 1, "y")
try(print, 1, 1)
try(print)
try(io.stdout, 1, 1)
try(setmetatable({}, {__name = "MyType"}), 1, 1)
try(setmetatable({}, {__index = function(_, i) return i * 2 end}), 1, 3)
try(setmetatable({}, {__len = function() return 2 end}))
try({1, 2, 3}, 2.0, 3.0)
try({1, 2, 3}, 2.5)
try({1, 2, 3}, math.maxinteger - 1, math.maxinteger)
try({1, 2, 3}, math.mininteger, math.maxinteger)

local string_meta = getmetatable("")
local string_index = string_meta.__index
string_meta.__index = function(s, i) return s .. i end
print(table.unpack("ab", 1, 3))
string_meta.__index = string_index

print(pcall(function() local t = nil; return table.unpack(t) end))
print(pcall(function() local x = 5; return table.unpack(x, 1, 2) end))
