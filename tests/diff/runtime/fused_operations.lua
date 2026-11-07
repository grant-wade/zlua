-- expect: pass
-- stage: runtime
-- feature: fused-operations
-- normalize: none

local function message(f, ...)
  local ok, err = pcall(f, ...)
  return ok and "ok" or tostring(err):gsub("^[^:]*:%d+: ", "")
end

local Base = {}
Base.__index = Base
function Base.new(x) return setmetatable({x = x}, Base) end
function Base:get() return self.x end
local Derived = setmetatable({}, {__index = Base})
Derived.__index = Derived
function Derived:twice() return self:get() * 2 end
local object = setmetatable({x = 21}, Derived)
print(object:get(), object:twice(), ("abc"):upper(), ("%d"):format(7))

local dynamic = setmetatable({}, {__index = function(_, key) return function(self, n) return key .. n end end})
print(dynamic:hello(1), dynamic:world(2))

local yielding = setmetatable({}, {
  __index = function(_, key) coroutine.yield("index " .. key) return function() return "called " .. key end end,
  __newindex = function(t, key, value) coroutine.yield("newindex " .. tostring(key)) rawset(t, key, value) end,
})
local co = coroutine.wrap(function()
  local a = yielding:method()
  yielding.field = 1
  yielding[3] = "three"
  local b = yielding[7]
  return a, rawget(yielding, "field"), rawget(yielding, 3), type(b)
end)
print(co()) print(co()) print(co()) print(co()) print(co())

local up = {count = 0, [1] = "one"}
local function bump() up.count = up.count + 1; up[2] = up[1] .. "!" return up.count, up[2] end
print(bump()) print(bump())

local proxy_log = {}
local proxy = setmetatable({}, {
  __index = function(_, key) proxy_log[#proxy_log + 1] = "get " .. tostring(key) return 0 end,
  __newindex = function(_, key, value) proxy_log[#proxy_log + 1] = "set " .. tostring(key) .. "=" .. tostring(value) end,
})
local function touch() proxy.a = proxy.b; proxy[1] = proxy[2]; proxy.flag = true; proxy.name = "n"; proxy.none = nil end
touch()
print(table.concat(proxy_log, " "))

local constants = {}
constants.int, constants.float, constants.str, constants.yes, constants.no = 1, 2.5, "s", true, false
constants.big = 1 << 40
constants.neg = -3
constants.str = "replaced"
constants.no = nil
local built = {a = 1, b = "two", c = false, d = nil, e = 3.5, [1] = "one", [2] = up, up = up}
print(constants.int, constants.float, constants.str, constants.yes, constants.no, constants.big, constants.neg)
print(built.a, built.b, built.c, built.d, built.e, built[1], built[2] == up, built.up == up)

local function varargs(...t)
  return t[1], t[2], t[3], t.n, t["n"]
end
print(varargs("a", "b"))

local wide = {}
wide[0] = "zero"; wide[1] = "one"; wide[255] = "255"; wide[256] = "256"; wide[4294967295] = "max32"; wide[4294967296] = "over"
print(wide[0], wide[1], wide[255], wide[256], wide[4294967295], wide[4294967296], wide[1.0], wide[2^32])

local missing = {}
local missing_up
print(message(function() return missing[1].x end))
print(message(function() return missing["key"]() end))
print(message(function() return missing[1000]() end))
print(message(function() missing_up.x = 1 end))
print(message(function() return missing_up.x end))
print(message(function() missing_up[1] = 1 end))
print(message(function() return missing_up[1] end))
print(message(function() missing:method() end))
print(message(function() local n; n:method() end))
print(message(function() local _ENV = nil; return global_name end))
print(message(function() local _ENV = nil; global_name = 1 end))
print(message(function() local _ENV = {}; global_name.x = 1 end))
print(message(function() local key = "k" return missing[key]() end))

local function env_conflict()
  local first, second = {}, {}
  local _ENV = first
  value, _ENV = 10, second
  return first.value, second.value
end
print(env_conflict())

local seen
local function upvalue_env()
  local result = {}
  seen = function() return result end
  return function()
    marker = "upvalue env"
    return marker
  end
end
print(upvalue_env()())
marker = nil
