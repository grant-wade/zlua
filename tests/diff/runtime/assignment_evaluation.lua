-- Assignments must not overwrite their destination while evaluating the RHS,
-- including calls, errors, short-circuiting, and yielding metamethods.
local value = 7
value = 3 + value
assert(value == 10)
value = (value + 2) * (value + 3)
assert(value == 156)

local function read() return value end
value = 10
value = (value + 2) + read()
assert(value == 22)

local function mutate()
  value = value + 1
  return 3
end
value = 10
value = value + mutate()
assert(value == 14)
value = 10
value = mutate() + value
assert(value == 14)

value = false
value = value and 7
assert(value == false)
value = value or 9
assert(value == 9)
value = (true and value) + 1
assert(value == 10)

local object = setmetatable({}, {
  __add = function()
    assert(value == 10)
    error("assignment failure", 0)
  end
})
assert(not pcall(function() value = object + 1 end))
assert(value == 10)

local thread = coroutine.create(function()
  local current = 41
  local operand = setmetatable({}, {
    __add = function()
      coroutine.yield(current)
      return 42
    end
  })
  current = operand + 1
  return current
end)
local ok, result = coroutine.resume(thread)
assert(ok and result == 41)
ok, result = coroutine.resume(thread)
assert(ok and result == 42)

local functions = {}
for i = 1, 4 do functions[i] = function() return i end end
for i = 1, 4 do assert(functions[i]() == i) end
print("assignment evaluation OK")
