-- name: sustained/vm/float_arithmetic
-- category: vm
-- expect: pass
-- iterations: 10
-- warmup: 2
-- Longer version of vm/float_arithmetic to reduce process startup noise.

local x = 0.5
for i = 1, 2000000 do
  x = x + i * 0.125
  x = x - i * 0.0625
end
print(string.format("%.3f", x))
