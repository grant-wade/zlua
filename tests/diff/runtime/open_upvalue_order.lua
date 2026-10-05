-- expect: pass
-- stage: runtime
-- feature: closure
-- normalize: none

-- Capture locals out of register order, close some scopes early, and unwind
-- through errors, then check every closure still sees its own variable.

local function make()
  local a, b, c, d = 1, 2, 3, 4
  local fd = function() d = d + 10; return d end
  local fb = function() b = b + 10; return b end
  local fs = {}
  do
    local inner = 100
    fs[1] = function() inner = inner + 1; return inner end
    local fc = function() c = c + 10; return c end
    fs[2] = fc
  end
  local fa = function() a = a + 10; return a end
  for i = 1, 3 do
    local x = i * 1000
    fs[#fs + 1] = function() x = x + 1; return x end
    if i == 2 then
      local y = -i
      fs[#fs + 1] = function() return y end
    end
  end
  return fa, fb, fd, fs, function() return a + b + c + d end
end

local fa, fb, fd, fs, sum = make()
print(fa(), fb(), fd(), sum())
for i = 1, #fs do io.write(tostring(fs[i]()), " ") end
print()
for i = 1, #fs do io.write(tostring(fs[i]()), " ") end
print()

-- Errors unwinding frames that hold open upvalues.
local function thrower(depth, acc)
  local v = depth
  acc[#acc + 1] = function() v = v + 1; return v end
  if depth == 0 then error("boom") end
  local w = depth * 2
  acc[#acc + 1] = function() return w end
  return thrower(depth - 1, acc) -- tail call keeps capturing
end
local closures = {}
local ok, err = pcall(thrower, 4, closures)
print(ok, (tostring(err):gsub("^.-:%d+: ", "")))
for i = 1, #closures do io.write(closures[i](), " ") end
print()

local function nested(depth, acc)
  local v = depth
  acc[#acc + 1] = function() return v end
  if depth == 0 then error("deep") end
  local ok, err = pcall(nested, depth - 1, acc)
  v = v + 100
  return ok, err
end
local list = {}
print(nested(3, list))
for i = 1, #list do io.write(list[i](), " ") end
print()

-- Coroutines keep their own open-upvalue lists.
local co = coroutine.wrap(function()
  local p, q = 1, 2
  local gq = function() return q end
  coroutine.yield(gq())
  local gp = function() return p end
  q = 20
  coroutine.yield(gp() + gq())
  p = 10
  return gp() + gq()
end)
print(co(), co(), co())

-- goto/break out of scopes with captured locals.
local saved = {}
for i = 1, 4 do
  local k = i
  saved[i] = function() return k end
  if i == 3 then break end
end
do
  local n = 0
  ::again::
  local m = n
  saved[#saved + 1] = function() return m end
  n = n + 1
  if n < 3 then goto again end
end
for i = 1, #saved do io.write(saved[i](), " ") end
print()
