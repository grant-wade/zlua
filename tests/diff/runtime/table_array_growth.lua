-- expect: pass
-- stage: runtime
-- feature: tables
-- normalize: none

local function keys(t)
  local list, count = {}, 0
  for k in pairs(t) do
    count = count + 1
    assert(count < 100, "pairs did not finish")
    list[#list + 1] = tostring(k)
  end
  table.sort(list)
  return table.concat(list, " ")
end

local a = {}
a[3] = "three"; a[2] = "two"; a[1] = "one"
a[4] = "four"
print(a[1], a[2], a[3], a[4], #a, keys(a))

local b = {}
b[5] = 5; b[3] = 3; b[1] = 1; b[2] = 2
for i = 4, 8 do b[i] = i end
print(#b, keys(b))

local c = {}
c[2] = "x"
c[1] = "y"
c[3] = "z"
print(c[1], c[2], c[3], #c, keys(c))

local weak = setmetatable({}, {__mode = "kv"})
local x, y, z = {}, {}, {}
weak[3] = z; weak[2] = y; weak[1] = x
for i = 4, 8 do weak[i] = {} end
collectgarbage()
print(weak[1] == x, weak[2] == y, weak[3] == z, keys(weak))

local function constructor(...)
  local t = {[3] = "k3", [2] = "k2", ...}
  return t[1], t[2], t[3], keys(t)
end
print(constructor("p1"))
print(constructor("p1", "p2", "p3", "p4"))
