-- expect: pass
-- stage: stdlib
-- feature: native calls from loops

local function show(...)
  print(select("#", ...), ...)
end

local text = "abcdefghij"
for i = -12, 12, 3 do
  show(text:byte(i))
  show(text:byte(i, i + 2))
  show(string.byte(text, i, -i))
  show(text:sub(i, i + 3), text:sub(-i))
end
show(text:byte())
show(("x"):byte(1, -1))
show((""):byte())

local nan = 0 / 0
local numbers = { 1, 2.5, -3, 2 ^ 53, 2 ^ 53 + 1, math.maxinteger, math.mininteger, 1 / 0, -1 / 0, nan, 0.0, -0.0 }
for i = 1, #numbers do
  for j = 1, #numbers do
    local a, b = numbers[i], numbers[j]
    show(math.max(a, b), math.min(a, b), math.max(a, b, 0), math.min(b, a, 0))
  end
end
show(pcall(math.max))
show(pcall(math.min, 1, "x"))

local t = { 10, 20, 30, 40, 50 }
local sum = 0
for i = 1, 200 do
  sum = sum + select("#", i, t) + rawlen(t) + (rawget(t, i % 7) or 0) + #type(i) + math.max(i, 100)
  if rawequal(t, t) and not rawequal(t, {}) then sum = sum + 1 end
end
print(sum)

local list = {}
for i = 1, 100 do
  table.insert(list, i)
  table.insert(list, 1, -i)
  if i % 3 == 0 then sum = sum + table.remove(list) + table.remove(list, 1) end
end
print(sum, #list, list[1], list[#list])

local function pack(...) return select("#", ...), ... end
for i = 1, 5 do
  show(math.max(pack(i, i * 2)))
  show(select(-1, pack(i, "tail")))
  show(tostring(select(2, pcall(error, { code = i })).code))
end

local function failure(f)
  local ok, message = pcall(f)
  return ok, (message:gsub("^.-:%d+: ", ""))
end

local out = io.stdout
for i = 1, 3 do
  print(out.missing, type(out.write), io.type(out))
  print(failure(function() return out:missing() end))
  print(failure(function() return out.missing.field end))
end

local meta = setmetatable({}, { __index = function(_, key) return "meta:" .. key end })
local object = setmetatable({}, { __index = meta })
for i = 1, 3 do
  print(object.name, object.len, getmetatable(object).__index == meta)
end
