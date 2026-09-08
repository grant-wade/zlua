-- name: sustained/vm/float_for
-- category: vm
-- expect: pass
-- iterations: 10
-- warmup: 2

local sum = 0.0
for i = 0.0, 99999.875, 0.125 do
  sum = sum + i
end
for i = 100000.0, 0.125, -0.125 do
  sum = sum - i
end
print(string.format("%.3f", sum))
