-- name: programs/sort_comparator
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- table.sort dominated by Lua comparator calls.

local N = 300000
local t = {}
local seed = 42
for r = 1, 4 do
for i = 1, N do seed = (seed * 1103515245 + 12345) % 2147483648; t[i] = seed end
table.sort(t, function(a, b) return a > b end)
end
print(t[1])
