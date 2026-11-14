-- name: sustained/string/sub_loop
-- category: string
-- expect: pass
-- iterations: 10
-- warmup: 2
-- Longer version of string/sub_loop to reduce process startup noise.

local source = string.rep("abcdefghijklmnopqrstuvwxyz", 200)
local sum = 0
for i = 1, 2000000 do
  local start = (i % 5000) + 1
  sum = sum + #string.sub(source, start, start + 7)
end
print(sum)
