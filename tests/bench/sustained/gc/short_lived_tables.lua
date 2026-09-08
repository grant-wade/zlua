-- name: sustained/gc/short_lived_tables
-- category: gc
-- expect: pass
-- iterations: 10
-- warmup: 2
-- Longer version of gc/short_lived_tables to reduce process startup noise.

local sum = 0
for i = 1, 1000000 do
  local t = { i, i + 1, tag = i % 13 }
  sum = sum + t[1] + t[2] + t.tag
end
print(sum)
