-- expect: pass
-- stage: runtime
-- feature: closures
-- normalize: none

local function counter(step)
  local c = 0
  return function() c = c + step; return c end
end

local total = 0
for i = 1, 2000 do
  local f = counter(i % 5)
  total = total + f() + f()
end
print("counters", total)

local fs = {}
for i = 1, 20 do
  fs[i] = function() return i end
end
local fresh = 0
for i = 1, 20 do fresh = fresh + fs[i]() end
print("loop variables", fresh)

local function pair()
  local value = 0
  local function get() return value end
  local function set(v) value = v end
  return get, set
end
local get1, set1 = pair()
local get2, set2 = pair()
set1(10)
set2(20)
print("independent", get1(), get2())

local function closed_after_return(x)
  local f = function() return x end
  x = x * 2
  return f, x
end
local f, doubled = closed_after_return(21)
print("closed value", f(), doubled)

local function nested(a)
  return function(b)
    return function(c) return a + b + c end
  end
end
print("nested", nested(1)(2)(3))

local weak = setmetatable({}, { __mode = "k" })
local function fill()
  for i = 1, 200 do
    local f = counter(i)
    weak[f] = true
    if i % 50 == 0 then collectgarbage("step") end
  end
end
fill()
collectgarbage()
local live = 0
for _ in pairs(weak) do live = live + 1 end
print("collected closures", live)

local made = {}
for round = 1, 5 do
  for i = 1, 100 do made[i] = counter(round) end
  collectgarbage("step")
end
local sum = 0
for i = 1, 100 do sum = sum + made[i]() end
print("after steps", sum)

local function missing(a, b, c) return a, b, c end
local function call_missing() return select('#', missing(1)), missing(1) end
print("missing", call_missing())
