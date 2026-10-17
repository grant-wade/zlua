-- Calls and returns that the plain fast loop handles directly: fixed
-- parameter lists, argument/result adjustment, returns nested under pending
-- pcall/metamethod/generic-for continuations, and debug views of temporaries.

local function add3(a, b, c) return a + b * 3 - c end
local function none() end
local function two(a) return a, a + 1 end
local function first(a, b) return a end

local x = 1
for i = 1, 200 do
  x = add3(x, i, i % 7) % 100003
end
print("loop", x)

-- Missing arguments are nil, extra arguments are dropped.
local function show(a, b, c) return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) end
print(show(1), show(1, 2), show(1, 2, 3, 4))

-- Result adjustment: fewer, more, and discarded results.
local a, b, c = two(5)
print(a, b, c)
local d = two(7)
print(d)
none(1, 2, 3)
print(first(two(10)))
print((two(20)))

-- Deep recursion stays exact.
local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end
print("fib", fib(15))

-- Returns inside pcall: inner frames return normally, the protected call
-- still completes at its own depth.
local function depth(n) if n == 0 then return 0 end return depth(n - 1) + 1 end
print(pcall(depth, 50))
print(pcall(function() return depth(10), depth(3) end))
print(pcall(function()
  local inner = depth(5)
  error("boom " .. inner, 0)
end))
print(select("#", pcall(none)))

-- Nested protected calls unwind to the right level.
local ok1, ok2, err = pcall(function()
  return pcall(function() return depth(4) + nil end)
end)
print(ok1, ok2, (tostring(err):gsub("^.-:%d+: ", "")))

-- Calls from metamethods and generic-for iterators return through
-- continuations below the fast frames.
local mt = { __index = function(_, key) return depth(3) + #key end }
local obj = setmetatable({}, mt)
print(obj.abc, obj.hello)
local sum = 0
for _, v in ipairs({ 1, 2, 3 }) do sum = sum + depth(v) end
print("ipairs", sum)
local function iter(limit, n)
  if n < limit then return n + 1, depth(n) end
end
for n, dn in iter, 3, 0 do print("iter", n, dn) end

-- Coroutines run calls on their own thread.
local co = coroutine.wrap(function(n)
  for i = 1, 3 do n = coroutine.yield(depth(n) + i) end
  return add3(n, 1, 1)
end)
print(co(2), co(3), co(4), co(5))

-- Temporaries visible to debug.getlocal stop at the callee's function slot.
local function probe()
  local name, value = debug.getlocal(2, 3)
  return name, value
end
local function caller(p)
  local q = p * 2
  return (q + 1) + select(2, probe())
end
print(pcall(caller, 4))
