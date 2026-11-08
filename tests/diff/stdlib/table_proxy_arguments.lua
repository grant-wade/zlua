-- expect: pass
-- stage: stdlib
-- feature: stdlib-table
-- normalize: none

-- Table functions accept non-tables whose metatables provide the operations
-- they use; strings need no __len.

local function try(name, f, ...)
  local r = table.pack(pcall(f, ...))
  for i = 1, r.n do r[i] = tostring(r[i]) end
  print(name, table.concat(r, " ", 1, r.n))
end

try("unpack string", table.unpack, "abc")
try("concat string", table.concat, "abc")
try("concat empty string", table.concat, "")
try("insert string", table.insert, "abc", 1)
try("remove string", table.remove, "abc")
try("sort string", table.sort, "abc")
try("move string", function() return type(table.move("abc", 1, 2, 1, {})) end)

local old = debug.getmetatable(0)
debug.setmetatable(0, {
  __index = function(_, i) return "n" .. i end,
  __len = function() return 2 end,
  __newindex = function(_, k, v) print("set", k, v) end,
})
try("unpack number", table.unpack, 0)
try("concat number", table.concat, 0, ",")
try("insert number", table.insert, 0, "x")
try("remove number", table.remove, 0)
try("move number", table.move, 0, 1, 2, 1)
try("move from number", function()
  local d = table.move(0, 1, 2, 1, {})
  return d[1], d[2]
end)
try("move to number", table.move, { 1, 2 }, 1, 2, 1, 0)

debug.setmetatable(0, { __index = function() end })
try("concat without len", table.concat, 0)
try("unpack without len", table.unpack, 0, 1, 2)
try("move to read-only", table.move, { 1 }, 1, 1, 1, 0)

debug.setmetatable(0, { __len = function() return 1 end })
try("unpack without index", table.unpack, 0)
try("insert without newindex", table.insert, 0, 1)
debug.setmetatable(0, old)

try("unpack file", table.unpack, io.stdout)
try("unpack missing", table.unpack)

local proxy = setmetatable({}, {
  __index = function(_, i) return i * 10 end,
  __len = function() return 3 end,
})
try("concat proxy", table.concat, proxy, "-")
try("unpack proxy", table.unpack, proxy, 1, 2)

local strings = setmetatable({}, {
  __index = function(_, i) return "s" .. i end,
  __len = function() return 2 end,
  __newindex = function() end,
})
try("remove string proxy", table.remove, strings)
