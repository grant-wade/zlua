-- name: programs/strings
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- String building, string methods, patterns, and formatting.

local t = {}
for i = 1, 200000 do
  t[#t+1] = tostring(i) .. "x" .. (i % 10)
end
local n = 0
for i = 1, #t do
  local s = t[i]
  if s:find("9x") then n = n + 1 end
  n = n + #s:upper() + s:byte(1)
end
local joined = table.concat(t, ",")
local c = 0
for w in joined:gmatch("[^,]+") do c = c + 1 end
print(n, c, #joined)
local parts = {}
for i = 1, 100000 do parts[i] = string.format("%d:%s:%5.2f", i, "k", i / 3) end
print(#table.concat(parts))
