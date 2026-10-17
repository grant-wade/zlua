-- name: programs/hash
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- String and sparse integer keys, deletion, and pairs.

local t = {}
for i = 1, 200000 do t["key" .. i] = i end
local sum = 0
for r = 1, 10 do
  for i = 1, 200000, 7 do sum = sum + t["key" .. i] end
end
local count = 0
for k, v in pairs(t) do count = count + v end
for i = 1, 200000, 2 do t["key" .. i] = nil end
local remain = 0
for k, v in pairs(t) do remain = remain + 1 end
local m = {}
for i = 1, 300000 do m[i * 7919 % 1000003] = i end
local ms = 0
for k, v in pairs(m) do ms = ms + v end
print(sum, count, remain, ms)
