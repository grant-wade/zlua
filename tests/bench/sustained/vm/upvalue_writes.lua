-- name: sustained/vm/upvalue_writes
-- category: vm
-- expect: pass
-- iterations: 10
-- warmup: 2

local sum = 0
local function accumulate()
  for i = 1, 3000000 do
    sum = sum + i
  end
end
accumulate()
print(sum)
