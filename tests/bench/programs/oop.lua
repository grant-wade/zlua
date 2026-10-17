-- name: programs/oop
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- Method calls through __index and short-lived objects.

local Point = {}
Point.__index = Point
function Point.new(x, y) return setmetatable({x = x, y = y}, Point) end
function Point:add(o) return Point.new(self.x + o.x, self.y + o.y) end
function Point:len2() return self.x * self.x + self.y * self.y end
local acc = Point.new(0, 0)
local s = 0
for i = 1, 2000000 do
  local p = Point.new(i, -i)
  acc = acc:add(p)
  s = s + p:len2() % 7
end
print(acc.x, acc.y, s)
