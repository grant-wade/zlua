-- name: sustained/vm/locals
-- category: vm
-- expect: pass
-- iterations: 10
-- warmup: 2
-- Longer version of vm/locals to reduce process startup noise.

local a, b, c, d = 1, 2, 3, 4
for i = 1, 3000000 do
  a = b + i
  b = c + a
  c = d + b
  d = a + c
end
print((a + b + c + d) % 1000000007)
