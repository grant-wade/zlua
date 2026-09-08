-- name: sustained/vm/function_calls
-- category: vm
-- expect: pass
-- iterations: 10
-- warmup: 2
-- Longer version of vm/function_calls to reduce process startup noise.

local function step(a, b, c)
  return (a + b * 3 - c) % 1000003
end

local x = 1
for i = 1, 1000000 do
  x = step(x, i, i % 17)
end
print(x)
