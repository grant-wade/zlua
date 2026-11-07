-- expect: pass
-- stage: runtime
-- feature: assignment
-- normalize: none

local i = 1
local t = {}
local function f() i = 2 return 0 end
t[i] = f()
print(t[1], t[2])

local a = {}
local j = 3
j, a[j] = j + 1, 20
print(j, a[3], a[4])

local u = {}
local k = 1
local function g() k = 5 return "v" end
u[k], u[k + 0] = g(), g()
print(u[1], u[5])

local original = {}
local tab = original
local function h() tab = {} return 9 end
tab.x = h()
print(original.x, tab.x)

local log = {}
local mt = setmetatable({}, {__newindex = function(_, key) log[#log + 1] = key end})
mt.a, mt.b, mt.c = 1, 2, 3
print(table.concat(log, ","))

local p, q = 1, 2
p, q = q, p
print(p, q)

local r = {1, 2}
local n = 1
r[n], n = 10, 2
print(r[1], r[2], n)

local s = {}
local m = 1
m, s[m] = 2, "first"
print(m, s[1], s[2])

local holder = {inner = {}}
local w = holder
w.inner.value, w = 7, nil
print(holder.inner.value, w)

local function env_swap()
  local saved = _ENV
  local replacement = {}
  marker, _ENV = "set", replacement
  local marked = saved.marker
  _ENV = saved
  return marked, replacement.marker
end
print(env_swap())
marker = nil
