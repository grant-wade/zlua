-- expect: pass
-- stage: runtime
-- feature: vararg
-- normalize: none

local function read(k, ...v) return v[k], v.n, ... end
for _, f in ipairs{read, assert(load(string.dump(read)))} do
  for _, k in ipairs{-1, 0, 1, 2, 3, 4, 1.0, 1.1, 'n', '1', print, {}} do
    local expected = table.pack(10, 20, 30)
    local value, n, a, b, c = f(k, 10, 20, 30)
    assert(value == expected[k] and n == 3)
    assert(a == 10 and b == 20 and c == 30)
  end
  assert(f(nil, 10) == nil)
  assert(f(0/0, 10) == nil)
end

local function escape(...v) return v end
local saved = escape(11, 22)
collectgarbage()
assert(saved[1] == 11 and saved.n == 2)
local function capture(...v) return function() return v[1] end end
assert(capture(42)() == 42)
local function mutate(...v) v[1] = 99; return ... end
assert(mutate(10) == 99)

-- Lua exposes an unmaterialized vararg binding as nil to debug.getlocal.
-- Direct vararg reads still use the arguments after debug.setlocal writes it.
local function change()
  local name, v = debug.getlocal(2, 1)
  assert(name == 'v' and v == nil)
end
local function inspect(...v)
  change()
  return v[1], ...
end
local first, second = inspect(10)
assert(first == 10 and second == 10)

local function replace()
  assert(debug.setlocal(2, 1, {77, n = 1}) == 'v')
end
local function reassigned(...v)
  replace()
  return v[1], ...
end
first, second = reassigned(10)
assert(first == 10 and second == 10)
print('named vararg reads ok')
