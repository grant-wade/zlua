-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none
-- gc-stress: skip
-- reason: allocates heavily on purpose; a full collection per allocation takes minutes

-- Old suspended threads are mutated without per-store barriers: open
-- upvalues written from another thread, resume values, and the coroutine's
-- own registers before a value-less yield. Minor collections must still trace
-- them, as Lua keeps threads on its grayagain list.

collectgarbage("generational")

local function minor(n)
  for _ = 1, n or 3 do collectgarbage("step") end
end

-- Allocate enough garbage that freed objects are likely to be reused.
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

-- 1. An open upvalue of an old suspended coroutine set from the main thread.
do
  local set
  local co = coroutine.create(function()
    local held = "init"
    set = function(v) held = v end
    while true do
      local expected = coroutine.yield()
      assert(type(held) == "table", "upvalue value collected")
      assert(sum(held) == expected, "upvalue value corrupted")
    end
  end)
  coroutine.resume(co)
  collectgarbage()
  for round = 1, 20 do
    set({ round, round * 2, round * 3 })
    minor(round % 4)
    churn()
    assert(coroutine.resume(co, round * 6))
  end
  print("open upvalue of suspended thread ok")
end

-- 2. A coroutine that drops out of the remembered set while running, then
-- stores young values in its own registers and yields nothing.
do
  local co = coroutine.create(function()
    for round = 1, 10 do
      minor(2)
      local young = { round, "r" .. round, { round } }
      local other = string.rep("x", round)
      coroutine.yield()
      assert(young[1] == round and young[2] == "r" .. round and young[3][1] == round)
      assert(other == string.rep("x", round))
    end
    return "done"
  end)
  collectgarbage()
  for _ = 1, 10 do
    assert(coroutine.resume(co))
    minor(3)
    churn()
  end
  print("value-less yield", select(2, coroutine.resume(co)))
end

-- 3. Resume values stored by an old coroutine across minor cycles.
do
  local co = coroutine.wrap(function(first)
    local kept = { first }
    while true do
      local value = coroutine.yield(#kept)
      if value == nil then break end
      kept[#kept + 1] = value
      minor(1)
    end
    local total = 0
    for i = 1, #kept do total = total + kept[i][1] + #kept[i].name end
    return total
  end)
  co({ 1, name = "a" })
  collectgarbage()
  for i = 2, 15 do
    co({ i, name = string.rep("n", i) })
    minor(2)
    churn()
  end
  print("resume values", co(nil))
end

-- 4. Closing an old open upvalue copies a young value into an old Upvalue.
do
  local get
  do
    local v = "old"
    get = function() return v end
    collectgarbage()
    v = { 7, 8, 9 }
  end
  minor(3)
  churn()
  print("closed main upvalue", sum(get()))

  local getters = {}
  local co = coroutine.create(function()
    local value = "old"
    getters[1] = function() return value end
    coroutine.yield()
    value = { 4, 5, 6 }
    return "finished"
  end)
  coroutine.resume(co)
  collectgarbage()
  print("closed coroutine upvalue", coroutine.resume(co))
  co = nil
  minor(3)
  churn()
  print("closed coroutine upvalue value", sum(getters[1]()))
end

-- 5. A thread that resumed another one stores young values through an open
-- upvalue of its resumer before both are suspended again.
do
  local outer
  local inner = coroutine.create(function()
    while true do
      local set = coroutine.yield()
      set({ 10, 20, 30 })
    end
  end)
  coroutine.resume(inner)
  outer = coroutine.create(function()
    local slot
    local function set(v) slot = v end
    for _ = 1, 5 do
      assert(coroutine.resume(inner, set))
      coroutine.yield()
      assert(sum(slot) == 60, "nested resume value lost")
      slot = nil
    end
  end)
  collectgarbage()
  for _ = 1, 5 do
    assert(coroutine.resume(outer))
    minor(3)
    churn()
  end
  print("nested resume ok", coroutine.status(outer))
end

-- 6. debug.setlocal into an old suspended coroutine.
do
  local co = coroutine.create(function()
    local a = "placeholder"
    coroutine.yield()
    return a
  end)
  coroutine.resume(co)
  collectgarbage()
  local name = debug.setlocal(co, 1, 1, { 11, 22 })
  minor(3)
  churn()
  local ok, value = coroutine.resume(co)
  print("setlocal", name, ok, sum(value))
end

-- 7. Many old coroutines, each mutated through an upvalue.
do
  local setters, threads = {}, {}
  for i = 1, 40 do
    threads[i] = coroutine.wrap(function()
      local slot
      setters[i] = function(v) slot = v end
      while true do
        coroutine.yield(slot and sum(slot) or 0)
      end
    end)
    threads[i]()
  end
  collectgarbage()
  for i = 1, 40 do setters[i]({ i, i }) end
  minor(3)
  churn()
  local total = 0
  for i = 1, 40 do total = total + threads[i]() end
  print("many coroutines", total)
end

-- 8. Pending call operands held by a suspended coroutine.
do
  local co = coroutine.create(function()
    local function combine(a, b, c) return sum(a) + sum(b) + sum(c) end
    return combine({ 1, 2 }, { 3, 4 }, coroutine.yield())
  end)
  coroutine.resume(co)
  collectgarbage()
  minor(3)
  churn()
  print("pending operands", coroutine.resume(co, { 5, 6 }))
end

-- 9. A weak probe on values only an old suspended coroutine holds.
do
  local probe = setmetatable({}, { __mode = "v" })
  local set
  local co = coroutine.create(function()
    local held
    set = function(v) held = v end
    coroutine.yield()
    return held.tag
  end)
  coroutine.resume(co)
  collectgarbage()
  set({ tag = "kept" })
  probe[1] = select(2, debug.getlocal(co, 1, 1))
  minor(3)
  churn()
  print("weak probe", probe[1] ~= nil, coroutine.resume(co))
end
