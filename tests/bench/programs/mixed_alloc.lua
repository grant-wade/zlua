-- name: programs/mixed_alloc
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- Interleaved tables, closures, and metatables.

local keep = {}
local s = 0
for i = 1, 2000000 do
  local t = {i, x = i}
  local function f() return t.x + i end
  local u = setmetatable({}, {__index = t})
  if i % 7 == 0 then keep[#keep + 1] = f end
  if #keep > 5000 then keep = {} end
  s = s + f() + u[1]
end
print(s)
