-- expect: pass
-- stage: runtime
-- feature: iteration-metamethods
-- normalize: none

local function pack(...) return {n = select('#', ...), ...} end
for _, factory in ipairs({pairs, ipairs}) do
  assert(not pcall(factory))
  for _, args in ipairs({pack(nil), pack(false), pack(42), pack(function() end), pack(coroutine.create(function() end))}) do
    local result = pack(factory(args[1]))
    assert(result.n == (factory == pairs and 4 or 3))
    assert(result[2] == args[1])
    assert(not pcall(result[1], result[2], result[3]))
    assert(not pcall(function() for k, v in factory(args[1]) do error('unexpected body') end end))
  end
end
assert(select('#', pairs({})) == 4)
assert(select('#', ipairs({})) == 3)
-- Strings are indexable through the string library, so their ipairs is empty.
local iter, state, key = ipairs('abc')
assert(select('#', iter(state, key)) == 1 and iter(state, key) == nil)
for k in ipairs('abc') do error('unexpected string element') end

for n = 0, 6 do
  local t = setmetatable({}, {__pairs = function(self, ...)
    assert(self ~= nil and select('#', ...) == 0)
    return table.unpack({11, 22, 33, 44, 55, 66}, 1, n)
  end})
  local r = pack(pairs(t))
  assert(r.n == 4)
  for i = 1, 4 do assert(r[i] == (i <= n and i * 11 or nil)) end
  local a, b, c, d, e, f = pairs(t)
  assert(a == r[1] and b == r[2] and c == r[3] and d == r[4] and e == nil and f == nil)
  assert((pairs(t)) == r[1])
  pairs(t)
end

-- Metatables for values other than tables also participate.
debug.setmetatable(42, {__pairs = function(value) return next, {value}, nil end})
for k, v in pairs(42) do assert(k == 1 and v == 42) end
debug.setmetatable(42, nil)
local callable = setmetatable({}, {__call = function(_, self) return next, {self}, nil end})
local t = setmetatable({}, {__pairs = callable})
for k, v in pairs(t) do assert(k == 1 and v == t) end

for _, backing in ipairs({{}, {false, 20}, {[1] = 10, [3] = 30}}) do
  for _, index in ipairs({backing, function(_, k) return backing[k] end}) do
    local t = setmetatable({}, {__index = index, __ipairs = function() error('__ipairs must be ignored') end})
    local iter, state, key = ipairs(t)
    assert(state == t and key == 0)
    local count = 0
    for k, v in ipairs(t) do
      count = count + 1
      local r = pack(iter(state, key))
      assert(r.n == 2 and r[1] == k and r[2] == v and v == backing[k])
      key = k
    end
    local r = pack(iter(state, key))
    assert(r.n == 1 and r[1] == nil and backing[count + 1] == nil)
  end
end
local marker = {}
for _, name in ipairs({'__pairs', '__index'}) do
  local t = setmetatable({}, {[name] = function() error(marker, 0) end})
  local ok, err
  if name == '__pairs' then ok, err = pcall(pairs, t)
  else
    local iter, state, key = ipairs(t)
    ok, err = pcall(iter, state, key)
  end
  assert(not ok and err == marker)
  ok, err = pcall(function() for k, v in (name == '__pairs' and pairs or ipairs)(t) do end end)
  assert(not ok and err == marker)
end

-- Lua 5.5's fourth pairs result is the generic-for closing value.
for _, mode in ipairs({'complete', 'break', 'error'}) do
  local closed, cause = 0, nil
  local closer = setmetatable({}, {__close = function(_, err) closed = closed + 1; cause = err end})
  local t = setmetatable({}, {__pairs = function() return next, {7, 8}, nil, closer, 'discard' end})
  local ok, err = pcall(function()
    for k, v in pairs(t) do
      if mode == 'break' then break end
      if mode == 'error' then error(marker, 0) end
    end
  end)
  assert(closed == 1)
  assert(ok == (mode ~= 'error'))
  assert(cause == (mode == 'error' and marker or nil))
end
print('iteration metamethods ok')
