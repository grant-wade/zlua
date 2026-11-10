-- name: sustained/stdlib/native_calls
-- category: stdlib
-- expect: pass
-- iterations: 10
-- warmup: 2

local max, type, select, rawlen, rawget = math.max, type, select, rawlen, rawget
local t = { 1, 2, 3 }
local sum = 0
for i = 1, 1000000 do
  sum = sum + max(i, 1) + #type(i) + select("#", i, 1) + rawlen(t) + rawget(t, 2)
end
print(sum)
