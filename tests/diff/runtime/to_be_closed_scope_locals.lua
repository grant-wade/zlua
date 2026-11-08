-- expect: pass
-- stage: runtime
-- feature: to-be-closed
-- normalize: none

-- Every local of a block is still visible to debug.getlocal while the block's
-- to-be-closed variables close, on each loop exit path.

local function names()
  local t = {}
  for i = 1, 20 do
    local n = debug.getlocal(3, i)
    if not n then break end
    if n:sub(1, 1) ~= "(" then t[#t + 1] = n end
  end
  return table.concat(t, ",")
end

local mt = { __close = function() print(names()) end }

local function block()
  do
    local x = 1
    local i <close> = setmetatable({}, mt)
    local y = 2
  end
end

local function while_break()
  while true do
    local x = 1
    local i <close> = setmetatable({}, mt)
    local y = 2
    break
  end
end

local function numeric_for()
  for k = 1, 2 do
    local x = 1
    local i <close> = setmetatable({}, mt)
    local y = 2
  end
end

local function repeat_until()
  local k = 0
  repeat
    local x = 1
    local i <close> = setmetatable({}, mt)
    local y = 2
    k = k + 1
  until k == 2
end

local function repeat_captured()
  local k = 0
  repeat
    local x = 1
    local i <close> = setmetatable({}, mt)
    local y = function() return x end
    k = k + 1
  until k == 2
end

local function if_block()
  if true then
    local x = 1
    local i <close> = setmetatable({}, mt)
    local y = 2
  end
end

local function goto_label()
  do
    local x = 1
    local i <close> = setmetatable({}, mt)
    goto done
  end
  ::done::
end

local function trailing_label()
  do
    local x = 1
    local i <close> = setmetatable({}, mt)
    ::finish::
  end
end

for _, f in ipairs({ block, while_break, numeric_for, repeat_until, repeat_captured, if_block, goto_label, trailing_label }) do
  print("--")
  f()
end

do
  local res = {}
  local function foo(a)
    repeat
      local x
      local i <close> = setmetatable({}, {
        __close = function()
          res[#res + 1] = debug.getlocal(2, 2)
          res[#res + 1] = debug.getlocal(2, 3)
          a = true
        end,
      })
    until a
  end
  foo(false)
  print(table.concat(res, ","))
end
