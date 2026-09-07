-- expect: pass
-- stage: runtime
-- feature: iteration-metamethods
-- normalize: none

local function pack(...) return {n = select('#', ...), ...} end
for n = 0, 6 do
  for _, tail in ipairs({false, true}) do
    local t = setmetatable({}, {__pairs = function(self)
      assert(coroutine.isyieldable())
      local x = coroutine.yield('first')
      assert(x == 17)
      coroutine.yield('second')
      return table.unpack({11, 22, 33, 44, 55, 66}, 1, n)
    end})
    local co = coroutine.create(function()
      if tail then return pairs(t) end
      local r = pack(pairs(t)); return table.unpack(r, 1, r.n)
    end)
    local ok, value = coroutine.resume(co)
    assert(ok and value == 'first')
    ok, value = coroutine.resume(co, 17)
    assert(ok and value == 'second')
    local r = pack(coroutine.resume(co))
    assert(r.n == 5 and r[1])
    for i = 1, 4 do assert(r[i + 1] == (i <= n and i * 11 or nil)) end
    assert(coroutine.status(co) == 'dead')
  end
end
-- A native __pairs can yield before adding a Lua frame.
local t = setmetatable({}, {__pairs = coroutine.yield})
local co = coroutine.create(function() return pairs(t) end)
local ok, value = coroutine.resume(co)
assert(ok and value == t)
local r = pack(coroutine.resume(co, 1, 2, 3, 4, 5))
assert(r.n == 5 and r[1] and r[2] == 1 and r[5] == 4)

-- Normalize before resuming an enclosing protected call or iterator call.
co = coroutine.create(function()
  local r = pack(pcall(pairs, t))
  assert(r.n == 5 and r[1] and r[2] == 10 and r[5] == nil)
  return 'done'
end)
assert(coroutine.resume(co))
ok, value = coroutine.resume(co, 10)
assert(ok and value == 'done')
co = coroutine.create(function()
  for k in pairs, t do assert(k == 10); break end
  return 'done'
end)
assert(coroutine.resume(co))
ok, value = coroutine.resume(co, 10)
assert(ok and value == 'done')

local marker = {}
co = coroutine.create(function()
  local t = setmetatable({}, {__pairs = function() coroutine.yield('before-error'); error(marker, 0) end})
  local ok, err = pcall(pairs, t)
  assert(not ok and err == marker)
  coroutine.yield('recovered')
  assert(select('#', pairs({})) == 4)
  return 'done'
end)
ok, value = coroutine.resume(co)
assert(ok and value == 'before-error')
ok, value = coroutine.resume(co)
assert(ok and value == 'recovered')
ok, value = coroutine.resume(co)
assert(ok and value == 'done')

for _, direct in ipairs({false, true}) do
  co = coroutine.create(function()
    local t = setmetatable({}, {__index = function()
      assert(not coroutine.isyieldable())
      return coroutine.yield('forbidden')
    end})
    if direct then local iter, state, key = ipairs(t); return iter(state, key) end
    for k, v in ipairs(t) do error('unexpected body') end
  end)
  local ok, err = coroutine.resume(co)
  assert(not ok and type(err) == 'string' and coroutine.status(co) == 'dead')
end

local closed = 0
co = coroutine.create(function()
  local t = setmetatable({}, {__pairs = function()
    coroutine.yield('setup')
    return next, {8}, nil, setmetatable({}, {__close = function() closed = closed + 1 end})
  end})
  for k, v in pairs(t) do assert(k == 1 and v == 8) end
end)
assert(coroutine.resume(co))
assert(coroutine.resume(co))
assert(closed == 1)
print('iteration coroutines ok')

-- Closing during setup closes the metamethod's locals, not an uninitialized
-- generic-for closing slot left over from previous register use.
closed = 0
co = coroutine.create(function()
  do local a, b, c, d = 1, 2, 3, 4 end
  for k, v in pairs(setmetatable({}, {__pairs = function()
    local guard <close> = setmetatable({}, {__close = function() closed = closed + 1 end})
    coroutine.yield('setup')
    error('must not resume')
  end})) do end
end)
assert(coroutine.resume(co))
assert(coroutine.close(co))
assert(closed == 1)

-- A protected call can also be inside pairs at the very same Lua frame depth.
local t = setmetatable({}, {__pairs = pcall, __call = function()
  coroutine.yield('inner protected')
  return 10, 20, 30, 40, 50
end})
co = coroutine.create(function() return pairs(t) end)
assert(coroutine.resume(co))
local r = pack(coroutine.resume(co))
assert(r.n == 5 and r[1] and r[2] and r[3] == 10 and r[4] == 20 and r[5] == 30)
co = coroutine.create(function() return pcall(pairs, t) end)
assert(coroutine.resume(co))
r = pack(coroutine.resume(co))
assert(r.n == 6 and r[1] and r[2] and r[3] and r[4] == 10 and r[5] == 20 and r[6] == 30)
t = setmetatable({}, {__pairs = pcall, __call = function()
  coroutine.yield('inner protected error')
  error(marker, 0)
end})
co = coroutine.create(function() return pairs(t) end)
assert(coroutine.resume(co))
r = pack(coroutine.resume(co))
assert(r.n == 5 and r[1] and r[2] == false and r[3] == marker and r[4] == nil and r[5] == nil)
