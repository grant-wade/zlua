-- name: programs/closures
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- Closure creation and upvalue reads and writes.

local function make(n)
  local c = 0
  return function() c = c + n; return c end
end
local s = 0
for i = 1, 3000000 do
  local f = make(i % 5)
  s = s + f() + f()
end
local fs = {}
for i = 1, 100 do fs[i] = make(i) end
for r = 1, 100000 do
  for i = 1, 100 do s = s + fs[i]() % 3 end
end
print(s)
