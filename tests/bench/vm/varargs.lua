-- name: vm/varargs
-- category: vm
-- expect: pass

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
for i = 1, 10000 do
  x = x + first_two(i, 1, 2) + forward(i, 1, 2) + count(i, 1, 2)
end
print(x)
