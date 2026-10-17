-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

-- An explicit collection marks stacks precisely, but registers below a
-- pending call are still live: call operands, table constructor entries,
-- concatenation operands, and the arguments of a native that calls back into
-- Lua. None of them may be collected or cleared.

local function f(a, b, c) return type(a), type(b), c end
local function first(t) return t[1] end

print(f({}, {}, collectgarbage()))
print(f({}, {}, (function() collectgarbage() return 1 end)()))
print(select('#', {}, {}, collectgarbage()))

do
  local function g(...) collectgarbage() return ... end
  print(type((g({}, {}))), f(g({}, { 1 })))
end

do
  local sorted = {}
  table.sort({ { 3 }, { 1 }, { 2 }, { 5 }, { 4 } }, function(a, b)
    collectgarbage()
    return a[1] < b[1]
  end)
  print("sort temporary", #sorted)
end

print(table.concat({ "a", (function() collectgarbage() return "b" end)() }, ","))

do
  local mt = { __concat = function(a, b) collectgarbage(); return "X" end }
  print(("p" .. "q") .. setmetatable({}, mt))
  print(string.rep("a", 3) .. tostring(collectgarbage()) .. string.rep("b", 2))
end

do
  local idx = setmetatable({}, { __index = function(_, k) collectgarbage(); return { k } end })
  print(idx.foo[1], f({}, idx.bar[1], 1))
end

print(pcall(function(a, b) collectgarbage() return a[1] + b[1] end, { 1 }, { 2 }))

do
  local function va(...)
    local n = select('#', ...)
    collectgarbage()
    local s = 0
    for i = 1, n do s = s + (select(i, ...))[1] end
    return s
  end
  print(va({ 1 }, { 2 }, { 3 }))
end

do
  local co = coroutine.wrap(function(a)
    local b = coroutine.yield({ a[1] + 1 })
    collectgarbage()
    return { b[1] * 2 }
  end)
  print(co({ 1 })[1])
  print(co({ (function() collectgarbage() return 21 end)() })[1])
end

do
  local obj = { v = 5 }
  function obj:m(t) collectgarbage() return self.v + t[1] end
  print(({ v = 7, m = obj.m }):m({ 1 }))
end

for k, v in next, { a = { 1 } }, nil do collectgarbage(); print(k, v[1]) end

do
  local tc = { { 1 }, { 2 }, (function() collectgarbage() return { 3 } end)(), { 4 } }
  print(tc[1][1], tc[2][1], tc[3][1], tc[4][1])
  local tc2 = { { 1 }, { 2 }, x = { 5 }, (function() collectgarbage() return 3 end)() }
  print(tc2[1][1], tc2[2][1], tc2.x[1], tc2[3])
  print(({ 1, 2, 3, (function() collectgarbage() return 4 end)() })[4])
end

do
  local function rc()
    local c <close> = setmetatable({}, { __close = function() collectgarbage() end })
    return { 10 }, { 20 }
  end
  local a1, a2 = rc()
  print(a1[1], a2[1], first(rc()), first(select(2, rc())))
end

do
  local t = setmetatable({}, { __newindex = function(t, k, v) collectgarbage(); rawset(t, k, v) end })
  t[{}] = { 1 }
  local n = 0
  for _, v in pairs(t) do n = n + v[1] end
  print("newindex", n)
end

do
  local t = {}
  t[{ 1 }] = (function() collectgarbage() return { 2 } end)()
  for k, v in pairs(t) do print("pending key", k[1], v[1]) end
end

do
  local s = {}
  for i = 1, 3 do s[i] = { i } end
  print(#table.pack(s[1], s[2], {}, collectgarbage()))
end

do
  local hh = (function() local u = { 8 }; return function() collectgarbage(); return u[1] end end)()
  print(hh())
end

print(xpcall(function() error({ 1 }) end, function(e) collectgarbage() return e[1] end))

do
  local ok, e = pcall(function()
    local t <close> = setmetatable({}, { __close = function(_, err) collectgarbage(); print("close error", err[1]) end })
    error({ 5 })
  end)
  print(ok, e[1])
end

-- Values above the pending call are dead and may still be collected.
do
  local weak = setmetatable({}, { __mode = "v" })
  do
    local dead = {}
    weak[1] = dead
  end
  collectgarbage()
  print("dead local", weak[1] == nil)
end
