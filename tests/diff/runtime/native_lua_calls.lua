-- expect: pass
-- stage: runtime
-- feature: calls
-- normalize: none

local function show(a, b, c) return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) end
print(pcall(show))
print(pcall(show, 1))
print(pcall(show, 1, 2, 3, 4))

local t = {}
for i = 1, 200 do t[i] = (i * 7919) % 211 end
local calls = 0
table.sort(t, function(a, b) calls = calls + 1; return a > b end)
print("sorted", t[1], t[200], calls > 0)

print((string.gsub("a1b22c333", "%d+", function(d) return "<" .. #d .. ">" end)))
print((string.gsub("x=1, y=2", "(%w+)=(%w+)", function(k, v, missing) return v .. k .. tostring(missing) end)))

local depth = 0
local function nest(n)
  depth = math.max(depth, n)
  if n == 0 then return 0 end
  local ok, value = pcall(nest, n - 1)
  return value + 1
end
print("nested pcall", nest(150), depth)

local function deep(n) if n == 0 then return "bottom" end return (select(2, pcall(deep, n - 1))) end
print(deep(100))

print(xpcall(function(a, b) return a + b end, debug.traceback, 2, 3))
print(select(2, xpcall(function() error({ code = 7 }) end, function(e) return e.code end)))

local wrapped = coroutine.wrap(function(a, b, c)
  local x = coroutine.yield(show(a, b, c))
  return show(x)
end)
print(wrapped(1, 2))
print(wrapped("resumed"))

local function many(...) return select('#', ...) end
local args = {}
for i = 1, 250 do args[i] = i end
print("many", pcall(many, table.unpack(args)))
