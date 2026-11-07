-- expect: pass
-- stage: runtime
-- feature: tail-calls
-- normalize: none

local function id(...) return ... end
local function pack(...) return select('#', ...), ... end
local function show(a, b, c) return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) end

local function fewer(a) return show(a) end
local function more(a, b) return show(a, b, a + b, "dropped") end
print(fewer(1), more(1, 2))

local function count(n, acc)
  if n == 0 then return acc end
  return count(n - 1, acc + 1)
end
print("deep", count(1000000, 0))

local function vararg_callee(a, ...) return a, select('#', ...), ... end
local function to_vararg(x) return vararg_callee(x, x + 1, x + 2) end
print(to_vararg(10))

local function from_vararg(...) return show(...) end
print(from_vararg(1, 2, 3, 4), from_vararg(), from_vararg(nil, 5))

local function from_vararg_frame(a, ...) return vararg_callee(a * 2, ...) end
print(from_vararg_frame(3, "x", "y"))
print(from_vararg_frame(4))

local function named(...v) return v.n, v[1], v[2] end
local function to_named(...) return named(...) end
print(to_named(7, 8, 9))
print(to_named())

local function multret_args() return show(id(1, 2, 3)) end
print(multret_args())
local function multret_pack() return pack(id()) end
print(multret_pack())
local function mixed_multret(x) return pack(x, id(x, x)) end
print(mixed_multret(5))

local function captured_then_tail(x)
  local get = function() return x end
  x = x + 1
  return id(get)
end
local getter = captured_then_tail(1)
print("closed", getter())

local function shared_then_tail()
  local value = 1
  local get = function() return value end
  local set = function(v) value = v end
  return pack(get, set)
end
local n, get, set = shared_then_tail()
set(42)
print("shared", n, get())

local function tail_info()
  local info = debug.getinfo(1, "t")
  return info.istailcall
end
local function call_info() return tail_info() end
print("istailcall", call_info(), (tail_info()))

local function where() return debug.traceback("tb", 1) end
local function through_tail() return where() end
local trace = through_tail()
print("tail frame", trace:find("(...tail calls...)", 1, true) ~= nil)

local function bad(x) return x.field end
local function tail_bad(x) return bad(x) end
local ok, message = pcall(tail_bad, nil)
print(ok, (message:gsub("^[^:]*:%d+: ", "")))

local mt = {}
local function new_object(x) return setmetatable({ x = x }, mt) end
local object = new_object(3)
print("native tail", getmetatable(object) == mt, object.x)
local function count_args(...) return select('#', ...) end
print("select tail", count_args(1, nil, 3))

local callable = setmetatable({}, { __call = function(self, a, b) return "called", a, b end })
local function tail_callable(a) return callable(a, a * 2) end
print(tail_callable(4))

local co = coroutine.wrap(function(a)
  local function yielder(x) return coroutine.yield(x + 1) end
  local b = yielder(a)
  return "done", b
end)
print(co(1))
print(co(10))

local events = {}
debug.sethook(function(event) events[event] = (events[event] or 0) + 1 end, "c")
count(5, 0)
debug.sethook()
print("hook tail calls", events["tail call"])

local function sum_points(points, i, acc)
  if i > #points then return acc end
  local p = points[i]
  return sum_points(points, i + 1, acc + p.x * p.y)
end
local points = {}
for i = 1, 50 do points[i] = { x = i, y = i % 3 } end
print("points", sum_points(points, 1, 0))
