-- name: sustained/stdlib/math_loop
-- category: stdlib
-- expect: pass
-- iterations: 10
-- warmup: 2
-- Longer version of stdlib/math_loop to reduce process startup noise.

local sum = 0
for i = 1, 1000000 do
  sum = sum + math.floor(math.sqrt(i * 3)) + math.abs((i % 17) - 8)
end
print(sum)
