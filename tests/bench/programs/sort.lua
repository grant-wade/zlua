-- name: programs/sort
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- table.sort with the default and a Lua comparator.

local N = 300000
local t = {}
local seed = 42
for i = 1, N do seed = (seed * 1103515245 + 12345) % 2147483648; t[i] = seed end
table.sort(t)
local u = {}
for i = 1, N do u[i] = t[N - i + 1] end
table.sort(u, function(a, b) return a > b end)
print(t[1], t[N], u[1])
