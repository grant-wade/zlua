-- expect: pass
-- stage: runtime
-- feature: metatable
-- normalize: none

-- Metatables cache absent events; every way of adding the event must be seen.

local function try(f)
  local ok, err = pcall(f)
  if ok then return ok, err end
  return ok, (tostring(err):gsub("^.-:%d+: ", ""))
end

local function check(label, mt, add)
  local t = setmetatable({}, mt)
  -- Prime the absence cache through the VM fast paths.
  for _ = 1, 3 do
    local _ = t.missing
    local _ = t[1]
    t.x = 1
    t.x = nil
    t[1] = 1
    t[1] = nil
    local _ = #t
  end
  add(mt)
  print(label, t.missing, t[1], #t)
  t.y = 5
  t[2] = 6
  print(label, rawget(t, "y"), rawget(t, 2))
end

local log = {}
local function index(_, k) return "idx:" .. tostring(k) end
local function newindex(_, k, v) log[#log + 1] = tostring(k) .. "=" .. tostring(v) end
local function len() return 99 end

local function add_all_rawset(mt)
  rawset(mt, "__index", index)
  rawset(mt, "__newindex", newindex)
  rawset(mt, "__len", len)
end

local function add_all_fields(mt)
  mt.__index = index
  mt.__newindex = newindex
  mt.__len = len
end

local function add_all_dynamic(mt)
  local names = {"__in" .. "dex", "__new" .. "index", "__l" .. "en"}
  local values = {index, newindex, len}
  for i = 1, 3 do mt[names[i]] = values[i] end
end

check("rawset", {}, add_all_rawset)
check("fields", {}, add_all_fields)
check("dynamic", {}, add_all_dynamic)
check("filled", {a = 1, b = 2, c = 3, d = 4, e = 5, f = 6}, add_all_fields)

-- Tombstoned event keys come back to life.
local mt = {__index = index, __newindex = newindex, __len = len}
mt.__index, mt.__newindex, mt.__len = nil, nil, nil
check("tombstone", mt, add_all_fields)
print(table.concat(log, " "))

-- table.* and next-based edits on a metatable.
local mt2 = {}
local obj = setmetatable({}, mt2)
print(obj.k)
table.insert(mt2, 1)
print(obj.k)
mt2.__index = {k = "via table"}
print(obj.k)
for k in next, mt2 do if k == "__index" then mt2[k] = nil end end
print(obj.k)
mt2.__index = function() return "back" end
print(obj.k)

-- Inheritance chain where an inner level later gains __index.
local base = {}
local mid = setmetatable({}, {__index = base})
local leaf = setmetatable({}, {__index = mid})
print(leaf.hello)
setmetatable(base, {__index = function(_, k) return "base:" .. k end})
print(leaf.hello)

-- Arithmetic, comparison, concat, call and tostring events added later.
local amt = {}
local a1, a2 = setmetatable({}, amt), setmetatable({}, amt)
print(try(function() return a1 + a2 end))
print(try(function() return a1 < a2 end))
print(a1 == a2)
amt.__add = function() return "add" end
amt.__lt = function() return true end
amt.__eq = function() return true end
amt.__concat = function() return "cat" end
amt.__call = function() return "called" end
amt.__unm = function() return "neg" end
amt.__name = "Named"
print(a1 + a2, a1 < a2, a1 == a2, a1 .. "x", a1(), -a1)
amt.__tostring = function() return "str" end
print(tostring(a1))

-- String metatable event added after use.
local smt = getmetatable("")
local str = "x"
print(try(function() return str() end))
rawset(smt, "__call", function(s) return "called " .. s end)
print(str())
rawset(smt, "__call", nil)
print(try(function() return str() end))

-- One-level __index tables used by the VM fast path.
local Class = {}
Class.__index = Class
function Class.get(self) return self.v end
local inst = setmetatable({v = 1}, Class)
local seen = {}
for i = 1, 6 do
  if i == 2 then Class.get = function(self) return self.v * 10 end end
  if i == 3 then Class.extra = "extra" end
  if i == 4 then setmetatable(Class, {__index = function(_, k) return "deep:" .. k end}) end
  if i == 5 then Class.__index = function(_, k) return "fn:" .. k end end
  if i == 6 then Class.__index = nil end
  local get = inst.get
  seen[#seen + 1] = tostring(type(get) == "function" and get(inst) or get) .. "/" .. tostring(inst.extra) .. "/" .. tostring(inst.other)
end
print(table.concat(seen, " "))
