-- Small tables and tables that have grown a hash index must agree on key
-- equality, tombstones, iteration, and collection of weak keys.
for size = 1, 12 do
  local t = {}
  for i = 1, size do t["key" .. i] = i end
  for i = 1, size do assert(t[string.sub("!key" .. i, 2)] == i) end
  local key = next(t)
  t[key] = nil
  next(t, key)
  t[key] = 17
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  assert(count == size)

  local weak = setmetatable({}, { __mode = "k" })
  local kept = {}
  for i = 1, size do
    local object = {}
    weak[object] = i
    if i % 2 == 0 then kept[i] = object end
  end
  collectgarbage("collect")
  count = 0
  for object, value in pairs(weak) do
    assert(kept[value] == object)
    count = count + 1
  end
  assert(count == size // 2)
  for i = 1, 12 do weak["new" .. i] = i end
  for i = 1, 12 do assert(weak["new" .. i] == i) end
end

local t = { [1.0] = "integer", [false] = "boolean" }
assert(t[1] == "integer" and t[false] == "boolean")
for i = 1, 8 do t["field" .. i] = i end
assert(t[1.0] == "integer" and t[false] == "boolean")
print("small table growth OK")
