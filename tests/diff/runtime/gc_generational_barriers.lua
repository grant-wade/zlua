-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none
-- gc-stress: skip
-- reason: allocates heavily on purpose; a full collection per allocation takes minutes

-- Old objects that receive young values must be revisited by minor
-- collections. Each case ages the parent with a full collection, stores
-- fresh values through one write path, runs minor steps, reuses memory, and
-- checks the contents.

collectgarbage("generational")

local function minor(n)
  for _ = 1, n or 3 do collectgarbage("step") end
end

local function churn()
  local junk = {}
  for i = 1, 300 do junk[i] = { i, tostring(i), { i } } end
  return #junk
end

local function sum(t)
  local s = 0
  for i = 1, #t do s = s + t[i] end
  return s
end

local function young(i)
  return { i, i + 1, name = "v" .. i }
end

local function check(v, i)
  return type(v) == "table" and sum(v) == 2 * i + 1 and v.name == "v" .. i
end

-- Table writes.
do
  local old = { 0 }
  local inserted = { "a", "b", "c" }
  local moved = {}
  local keyed = {}
  collectgarbage()
  for round = 1, 12 do
    rawset(old, 1, young(round))
    old.field = young(round + 100)
    table.insert(inserted, 2, young(round + 200))
    table.move({ young(round + 300), young(round + 400) }, 1, 2, 1, moved)
    keyed[young(round + 500)] = young(round + 600)
    minor(round % 3 + 1)
    churn()
    assert(check(old[1], round) and check(old.field, round + 100))
    assert(check(inserted[2], round + 200))
    assert(check(moved[1], round + 300) and check(moved[2], round + 400))
    local count = 0
    for k, v in pairs(keyed) do
      assert(check(k, k[1]) and check(v, k[1] + 100))
      count = count + 1
    end
    assert(count == round)
  end
  print("table writes", #inserted, #moved)
end

-- table.move within an old table and table.remove keep shifted values.
do
  local old = {}
  for i = 1, 8 do old[i] = "old" .. i end
  collectgarbage()
  for i = 1, 8 do old[i] = young(i) end
  table.move(old, 1, 8, 3)
  table.remove(old, 1)
  minor(3)
  churn()
  local ok = true
  for i = 3, 9 do ok = ok and check(old[i], i - 1) end
  print("table move/remove", ok, #old)
end

-- Metatables installed on old tables.
do
  local old = {}
  collectgarbage()
  setmetatable(old, { __index = { answer = young(42) }, __len = function() return 99 end })
  minor(3)
  churn()
  print("setmetatable", check(old.answer, 42), #old)

  local mt = { __index = {} }
  local child = setmetatable({}, mt)
  collectgarbage()
  mt.__index = { value = young(7) }
  mt.__call = function(_, x) return x * 2 end
  minor(3)
  churn()
  print("old metatable fields", check(child.value, 7), child(21))
end

-- Upvalues changed by the debug library.
do
  local captured = "old"
  local function read() return captured end
  collectgarbage()
  debug.setupvalue(read, 1, young(9))
  minor(3)
  churn()
  print("setupvalue", check(read(), 9))

  local a_value, b_value = "a", "b"
  local function a() return a_value end
  collectgarbage()
  local function b() return b_value end
  b_value = young(13)
  debug.upvaluejoin(a, 1, b, 1)
  b = nil
  minor(3)
  churn()
  print("upvaluejoin", check(a(), 13))
end

-- Young closures and strings stored in old tables.
do
  local registry = {}
  collectgarbage()
  for i = 1, 10 do
    local captured = young(i)
    registry[i] = function() return captured end
    registry["s" .. i] = string.rep("z", i) .. i
  end
  minor(3)
  churn()
  local ok = true
  for i = 1, 10 do
    ok = ok and check(registry[i](), i) and registry["s" .. i] == string.rep("z", i) .. i
  end
  print("closures and strings", ok)
end

-- Ephemeron tables with old keys, young values, and keys only an old
-- suspended coroutine holds.
do
  local eph = setmetatable({}, { __mode = "k" })
  local old_key = {}
  local set
  local co = coroutine.create(function()
    local key
    set = function(v) key = v end
    coroutine.yield()
    return eph[key]
  end)
  coroutine.resume(co)
  collectgarbage()
  eph[old_key] = young(1)
  local key = {}
  eph[key] = young(2)
  set(key)
  key = nil
  minor(3)
  churn()
  local ok, value = coroutine.resume(co)
  print("ephemeron", check(eph[old_key], 1), ok, check(value, 2))
end

-- A finalizer resurrects objects into an old table.
do
  local saved = {}
  local finalized = 0
  local mt = { __gc = function(o)
    finalized = finalized + 1
    saved[#saved + 1] = o
  end }
  collectgarbage()
  for i = 1, 6 do
    setmetatable({ child = young(i), index = i }, mt)
  end
  collectgarbage()
  minor(3)
  churn()
  table.sort(saved, function(a, b) return a.index < b.index end)
  local ok = #saved == 6
  for i = 1, #saved do ok = ok and check(saved[i].child, i) end
  print("resurrection", finalized, ok)
  saved = nil
end

-- Weak values held only by old objects survive minor collections.
do
  local weak = setmetatable({}, { __mode = "v" })
  local holder = {}
  collectgarbage()
  for i = 1, 10 do
    local v = young(i)
    holder[i] = v
    weak[i] = v
  end
  minor(3)
  churn()
  local count = 0
  for i = 1, 10 do
    if weak[i] and check(weak[i], i) then count = count + 1 end
  end
  print("weak values held by old table", count)
  holder = nil
  collectgarbage()
  print("weak values released", next(weak) == nil)
end
