-- name: sustained/table/array_reads
-- category: table
-- expect: pass
-- iterations: 10
-- warmup: 2
-- Longer version of table/array_reads to reduce process startup noise.

local t = {}
for i = 1, 1000 do
  t[i] = i * 3
end

local sum = 0
for i = 1, 3000000 do
  local index = (i % 1000) + 1
  sum = sum + t[index]
end
print(sum)
