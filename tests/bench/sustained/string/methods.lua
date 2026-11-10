-- name: sustained/string/methods
-- category: string
-- expect: pass
-- iterations: 10
-- warmup: 2

local text = "abcdefghijklmnopqrstuvwxyz"
local sum = 0
for i = 1, 1000000 do
  local at = (i % 20) + 1
  sum = sum + text:byte(at) + #text:sub(at, at + 3) + text:len()
end
print(sum)
