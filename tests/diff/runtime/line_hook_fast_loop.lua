-- expect: pass
-- stage: runtime
-- feature: debug-hooks
-- normalize: none

local lines = {}
local function hook(_, line) lines[#lines + 1] = line end
local function on() debug.sethook(hook, "l") end
local function off() debug.sethook() end

local function f(n)
  on()
  local x = 0
  off()
  for i = 1, n do x = x + i end
  on()
  x = x + 1
  off()
  return x
end

local function h(n)
  on()
  local x = 0
  for i = 1, n do
    if i == 2 then off() end
    if i == 4 then on() end
    x = x + i
  end
  off()
  return x
end

print(f(5), h(6))
print(table.concat(lines, " "))
