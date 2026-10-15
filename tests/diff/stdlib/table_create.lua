-- expect: pass
-- stage: stdlib
-- feature: stdlib-table
-- normalize: none

-- table.create(nseq [, nrec]) is standard in Lua 5.5.

local function try(...)
  local ok, result = pcall(table.create, ...)
  if ok then
    print(select("#", ...), "ok", type(result), #result, next(result))
  else
    print(select("#", ...), "err", result)
  end
end

try(0)
try(10)
try(10, 5)
try(0, 0)
try(3.0)
try(2.0, 4.0)
try("4")
try("4", "2")
try(0, nil)

try(-1)
try(0, -1)
try(-1, -1)
try(math.mininteger)
try(math.maxinteger)
try(0, math.maxinteger)
try(0, 2^31 - 1)
try(0, 2^30 + 1)
try(2^31)
try(0, 2^31)
try(2^63)
try(1.5)
try(0, 1.5)
try("x")
try(0, "y")
try("1.5")
try(nil)
try()
try({})
try(0, {})
try(true)
try(-1, "y")
try(2^31, {})
try("2.0", "0x10")
try(" 3 ")

local t = table.create(4, 4)
print(#t, next(t))
for i = 1, 4 do t[i] = i * i end
t.x = "x"
print(#t, t[1], t[4], t.x)
t[5] = 25
print(#t, t[5])

local mt = setmetatable(table.create(2), { __index = function(_, k) return k * 2 end })
print(mt[1], rawget(mt, 1))

-- Exhausted traversal of an empty table yields a single nil.
print(select("#", next(table.create(8, 8))))
