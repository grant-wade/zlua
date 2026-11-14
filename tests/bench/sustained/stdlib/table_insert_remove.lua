-- name: sustained/stdlib/table_insert_remove
-- category: stdlib
-- expect: pass
-- iterations: 10
-- warmup: 2

local insert, remove = table.insert, table.remove
local t = {}
local sum = 0
for i = 1, 1000000 do
  insert(t, i)
  insert(t, i + 1)
  sum = sum + remove(t) + remove(t)
end
print(sum, #t)
