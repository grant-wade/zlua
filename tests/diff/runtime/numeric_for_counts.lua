-- expect: pass
-- stage: runtime
-- feature: numeric-for
-- normalize: none

local function trips(a, b, c)
  local n, last = 0, nil
  for i = a, b, c do
    n = n + 1
    last = i
    if n > 10 then break end
  end
  return n, last
end

local max, min = math.maxinteger, math.mininteger
print(trips(1, 3, 1))
print(trips(3, 1, -1))
print(trips(1, 0, 1))
print(trips(0, 1, -1))
print(trips(1, 10, 3))
print(trips(10, 1, -3))
print(trips(max - 2, max, 1))
print(trips(min + 2, min, -1))
print(trips(max - 5, max, 2))
print(trips(min + 5, min, -2))
print(trips(min, max, max))
print(trips(max, min, min))
print(trips(max, min, -max))
print(trips(0, max, max // 3))
print(trips(1, 3.5, 1))
print(trips(3, 0.5, -1))
print(trips(1, -math.huge, 1))
print(trips(1, math.huge, max))
print(trips(1.0, 3, 1))
print(trips(1, 2, 0.5))
print((pcall(trips, 1, 2, 0)))
print((pcall(trips, 1, "x", 1)))

local count = 0
for i = 1, 3 do
  for j = i, 3 do
    for k = j, 1, -1 do count = count + i * j * k end
  end
end
print(count)

local function nested(n)
  local total = 0
  for i = 1, n do total = total + i end
  return total
end
local sum = 0
for i = 0, 5 do sum = sum + nested(i) end
print(sum)
local n = 0
for i = 1, 10 do
  n = n + 1
  if i == 2 then
    for k = 1, 10 do
      local name = debug.getlocal(1, k)
      if name == "i" then debug.setlocal(1, k, 8) break end
    end
  end
end
print(n)
