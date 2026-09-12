-- expect: pass
-- stage: runtime
-- feature: stdlib-math
-- normalize: none

local inputs = {
  math.mininteger, math.maxinteger, 0, -0.0, 3, -3.5,
  math.huge, -math.huge, 0/0, "3.5", false, {}
}
for _, fn in ipairs({ math.abs, math.ceil, math.floor, math.sqrt }) do
  local function wrapped(value)
    local result = fn(value)
    return result
  end
  for _, value in ipairs(inputs) do
    -- A direct protected native call and one issued by Lua must agree.
    local ok1, expected = pcall(fn, value)
    local ok2, actual = pcall(wrapped, value)
    assert(ok1 == ok2)
    if ok1 then
      assert(math.type(actual) == math.type(expected))
      assert(actual == expected or (actual ~= actual and expected ~= expected))
      if actual == 0 then assert(1/actual == 1/expected) end
      local a, b, c = wrapped(value)
      assert((a == actual or a ~= a) and b == nil and c == nil)
      assert(select("#", wrapped(value)) == 1)
    end
  end
end

local function three() return 81, "ignored", true end
for i = 1, 100 do
  assert(math.floor(math.sqrt(i * i)) == i)
  assert(math.sqrt(three()) == 9)
  math.abs(-i) -- discarded results must not affect a later call
  local a, b = math.ceil(i + 0.5)
  assert(a == i + 1 and b == nil)
end

local events = 0
debug.sethook(function()
  if debug.getinfo(2, "f").func == math.sqrt then events = events + 1 end
end, "cr")
local result = math.sqrt(81)
debug.sethook()
assert(result == 9 and events == 2)
print("numeric native calls ok")
