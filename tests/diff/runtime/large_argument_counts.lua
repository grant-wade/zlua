-- expect: pass
-- stage: runtime
-- feature: calls
-- normalize: none

-- Calls and returns carry more values than fit in a 16-bit count, up to the
-- stack limit.
local N = 70000
local unpack = table.unpack
local t = {}
for i = 1, N do t[i] = i end

local function count(...) return select("#", ...) end
local function last(...) return (select(-1, ...)) end
local function id(...) return ... end
local function tail(...) return id(...) end
local function nontail(...) local a, b = id(...) return a, b, select("#", ...) end

print(pcall(function() return select("#", unpack({}, 1, N)) end))
print(count(unpack(t)), last(unpack(t)), select(N, unpack(t)))
print(count(tail(unpack(t))), count(id(unpack(t))), nontail(unpack(t)))
print(count(pcall(id, unpack(t))), count(xpcall(id, print, unpack(t))))
print(table.pack(unpack(t)).n, #{unpack(t)}, (function(...) return #{...} end)(unpack(t)))
print(math.max(unpack(t)), math.min(unpack(t)), count(assert(unpack(t))))
print(count(load("return ...")(unpack(t))), count(select(2, unpack(t))))
print(#string.char(unpack(setmetatable({}, {__index = function() return 65 end}), 1, N)))
print(count(string.byte(string.rep("a", N), 1, -1)), count(utf8.codepoint(string.rep("a", N), 1, -1)))
print(#utf8.char(unpack(t)))

local callable = setmetatable({}, {__call = function(_, ...) return count(...) end})
print(callable(unpack(t)), (function() return callable(unpack(t)) end)())

local co = coroutine.wrap(function(...)
  local received = count(...)
  return received, count(coroutine.yield(...))
end)
print(count(co(unpack(t))))
print(co(unpack(t)))
print(count(coroutine.resume(coroutine.create(id), unpack(t))))

local function norm(ok, message)
  print(ok, (message:gsub("^[^:]*:%d+: ", "")))
end
norm(pcall(function() return unpack({}, 1, 2000000) end))
norm(pcall(function() return count(unpack({}, 1, 999990)) end))
print(pcall(string.byte, string.rep("a", 1100000), 1, -1))
print(pcall(utf8.codepoint, string.rep("a", 1100000), 1, -1))
