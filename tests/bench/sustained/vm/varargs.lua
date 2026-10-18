-- name: sustained/vm/varargs
-- category: vm
-- expect: pass
-- iterations: 10
-- warmup: 2
-- Longer version of vm/varargs to reduce process startup noise.

local function sum(a, b, c)
  return a + b + c
end

local function first_two(...)
  local a, b = ...
  return a + b
end

local function forward(...)
  return sum(...)
end

local function count(...)
  return select('#', ...) + select(2, ...)
end

local x = 0
for i = 1, 1000000 do
  x = x + first_two(i, 1, 2) + forward(i, 1, 2) + count(i, 1, 2)
end
print(x)
