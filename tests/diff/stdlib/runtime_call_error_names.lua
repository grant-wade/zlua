-- expect: pass
-- stage: stdlib
-- feature: argument-error-diagnostics
-- normalize: none

-- Library functions that the runtime calls rather than a Lua call
-- instruction: message handlers, coroutine bodies, __call targets, iterator
-- callbacks, and __close handlers run by error unwinding. Their argument
-- errors are positioned and named like Lua's luaL_argerror.

local function check(ok, ...)
  local out = {tostring(ok)}
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    out[#out + 1] = type(value) == "string" and (value:gsub("[^%s]*:(%d+): ", "chunk:%1: ")) or tostring(value)
  end
  print(table.concat(out, "\t"))
end

check(pcall(string.format, "%d", {}))
check(xpcall(string.format, function(m) return m end, "%d", {}))

-- Message handlers see the function that raised the error as their caller.
check(xpcall(function() error({}) end, string.upper))
check(xpcall(function() error({}) end, math.floor))
check(xpcall(function() local t = setmetatable({}, {__index = function() error({}) end}) return t.x end, string.upper))
check(xpcall(function() local x = {} .. 1 end, string.upper))
check(xpcall(function() local x = {} .. 1 end, math.floor))
check(xpcall(function() string.rep() end, string.upper))
check(xpcall(error, string.upper, {}))
check(xpcall(string.rep, string.upper))
check(coroutine.wrap(function() return xpcall(function() error({}) end, string.upper) end)())

-- Coroutine bodies have no caller.
check(coroutine.resume(coroutine.create(string.rep)))
check(coroutine.resume(coroutine.create(string.rep), "x", {}))
check(pcall(coroutine.wrap(math.floor), {}))
check(coroutine.resume(coroutine.create(error), "x", 1))
check(coroutine.resume(coroutine.create(error), "x", 2))
check(coroutine.wrap(pcall)(string.rep))
check(coroutine.wrap(xpcall)(string.rep, function(m) return m end))

-- Arguments added by __call are extra arguments.
local rep = setmetatable({}, {__call = string.rep})
local rep2 = setmetatable({}, {__call = rep})
local t = {f = rep}
check(pcall(function() return rep() end))
check(pcall(function() local r = rep("x") return r end))
check(pcall(function() local r = t.f() return r end))
check(pcall(function() local r = t:f(1) return r end))
check(pcall(function() local r = rep2(1, 2) return r end))
check(pcall(rep))
check(pcall(rep2, 1))
check(pcall(function() local r = setmetatable({}, {__call = string.format})("%d", "x") return r end))
check(pcall(function() local r = setmetatable({}, {__call = string.format})("x", "%d", "x") return r end))
check(pcall(function() for k in rep do end end))
check(pcall(function() return 1 + setmetatable({}, {__add = rep}) end))
check(pcall(function() local x <close> = setmetatable({}, {__close = rep}) end))
check(pcall(string.gsub, "x", "x", rep))

-- Library iterators call metamethods as native code.
local floor_index = setmetatable({}, {__index = math.floor})
check(pcall(function() for i, v in ipairs(floor_index) do end end))
check(pcall(function() for i, v in ipairs(setmetatable({}, {__index = floor_index})) do end end))
check(pcall(ipairs(floor_index), floor_index, 0))
check(pcall(function() for p, c in utf8.codes("ab\xff") do end end))
check(pcall(function() for k in next, 1 do end end))

-- __close handlers run by error unwinding have a native caller; those run
-- by leaving a block do not.
check(pcall(function() local x <close> = setmetatable({}, {__close = math.floor}) end))
check(pcall(function() local x <close> = setmetatable({}, {__close = math.floor}) error("e") end))
check(pcall(function() local x <close> = setmetatable({}, {__close = math.floor}) local y = {} .. 1 end))
local co = coroutine.create(function() local x <close> = setmetatable({}, {__close = math.floor}) coroutine.yield() end)
coroutine.resume(co)
check(coroutine.close(co))

check(pcall(collectgarbage, "nope"))
check(pcall(collectgarbage, 1))
check(pcall(collectgarbage, {}))
check(pcall(debug.getinfo, {}))
check(pcall(debug.getinfo, coroutine.create(print), {}))
check(pcall(debug.getinfo, 1.5))
check(debug.getinfo("1", "l").currentline)
check(pcall(debug.sethook, print))
check(pcall(debug.sethook, coroutine.create(print), print, {}))
