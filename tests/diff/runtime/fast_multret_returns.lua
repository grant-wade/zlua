-- expect: pass
-- stage: runtime
-- feature: multiple-returns
-- normalize: none

local function none() end
local function one(x) return x end
local function three(x) return x, x + 1, x + 2 end
local function nils() return nil, nil end

print(select('#', none()), select('#', one(1)), select('#', three(1)), select('#', nils()))
print(three(10))
print(one(5), three(20))

local t = { three(1) }
print(#t, t[1], t[3])
local u = { 0, three(4) }
print(#u, u[4])

local function pass(...) return select('#', ...), ... end
print(pass(three(7)))
print(pass(none()))

print(pcall(three, 30))
print(pcall(none))
print(pcall(one, nil))

local function sum(a, b, c) return (a or 0) + (b or 0) + (c or 0) end
local total = 0
for i = 1, 1000 do total = total + sum(three(i)) end
print("total", total)

local results = {}
for i = 1, 100 do
  local ok, a, b, c = pcall(three, i)
  results[#results + 1] = a + b + c
end
print("pcall results", #results, results[100])

local co = coroutine.wrap(function(...)
  local function yield_three(x) return coroutine.yield(x), x end
  print("resumed", yield_three(...))
  return three(100)
end)
co(1)
print(co("a", "b"))
