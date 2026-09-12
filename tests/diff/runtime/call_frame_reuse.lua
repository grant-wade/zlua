-- expect: pass
-- stage: runtime
-- feature: call-frames
-- normalize: none

local function values(a, b, c)
  return a, b, c
end

local function nested(a, b, c)
  local x, y, z = values(a, b, c)
  return x, y, z
end

local function none(a)
  local ignored = a
end

local function recursive(n)
  if n == 0 then return 7 end
  return 1 + recursive(n - 1)
end

-- Reuse stack slots with different argument and result counts after growth.
for i = 1, 8 do
  assert(recursive(64) == 71)
  local a, b, c, d = nested(i, i + 1, i + 2, "ignored")
  assert(a == i and b == i + 1 and c == i + 2 and d == nil)
  a, b, c = nested(i)
  assert(a == i and b == nil and c == nil)
  a, b, c = nested()
  assert(a == nil and b == nil and c == nil)
  a, b = none(i)
  assert(a == nil and b == nil)
  nested(i, i, i)
  assert(select("#", nested(i, nil, i)) == 3)
  assert(select("#", none(i)) == 0)
end

-- Returning through a host/protected call must stop at its saved frame depth.
local function protected(n)
  local result = recursive(n)
  return result, "done"
end
for i = 1, 8 do
  local ok, result, ending = pcall(protected, i)
  assert(ok and result == i + 7 and ending == "done")
end

-- A return must close captured slots before a later call reuses them.
local function capture(value)
  local result = function() return value end
  return result
end
local first = capture(31)
local second = capture(42)
assert(first() == 31 and second() == 42)

-- A resumed Lua return can complete a pending native continuation.
local object = setmetatable({}, {
  __add = function(_, value)
    coroutine.yield("add")
    local result = recursive(value)
    return result
  end
})
local worker = coroutine.create(function()
  local result = object + 2
  return result, nested(3, 4, 5)
end)
local ok, value = coroutine.resume(worker)
assert(ok and value == "add")
local a, b, c
ok, value, a, b, c = coroutine.resume(worker)
assert(ok and value == 9 and a == 3 and b == 4 and c == 5)
assert(coroutine.status(worker) == "dead")
print("call frame reuse ok")
