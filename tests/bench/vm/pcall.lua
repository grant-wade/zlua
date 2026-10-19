-- name: vm/pcall
-- category: vm
-- expect: pass

local function step(x)
  return x + 1
end

local function fail(x)
  error(x)
end

local x = 0
for i = 1, 10000 do
  local ok, value = pcall(step, i)
  x = x + value
  if not pcall(fail, i) then x = x + 1 end
  local _, y = xpcall(step, print, i)
  x = x + y
end
print(x)
