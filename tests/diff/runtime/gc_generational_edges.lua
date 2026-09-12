-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

collectgarbage('stop')
collectgarbage('generational')
local first = setmetatable({}, {__mode='k'})
local second = setmetatable({}, {__mode='k'})
local holder = {}
collectgarbage('collect')
for i=1,30 do
  local key, middle = {}, {}
  holder.key = key
  first[key] = middle
  second[middle] = {i}
  for j=1,3 do collectgarbage('step', 0) end
  assert(second[first[holder.key]][1] == i)
  holder.key = nil
end
collectgarbage('collect')
assert(next(first) == nil and next(second) == nil)

local mode = {__mode='v'}
local weak = setmetatable({}, mode)
collectgarbage('collect')
for i=1,30 do
  weak.item = {i}
  mode.__mode = ''
  for j=1,3 do collectgarbage('step', 0) end
  assert(weak.item[1] == i)
  mode.__mode = 'v'
  collectgarbage('collect')
  assert(weak.item == nil)
end

local finalized = 0
local mt = {__gc=function(t)
  assert(t.child[1] == 42)
  finalized = finalized + 1
  for _, option in ipairs({'collect', 'step', 'count', 'isrunning', 'stop', 'restart', 'incremental', 'generational'}) do
    assert(collectgarbage(option) == nil)
  end
  assert(collectgarbage('param', 'pause', 10) == -1)
  assert(not pcall(collectgarbage, 'param', 'missing', 1))
  assert(not pcall(collectgarbage, 'step', 1.5))
end}
for i=1,20 do
  setmetatable({child={42}}, mt)
  collectgarbage('step', 0)
end
collectgarbage('collect')
assert(finalized == 20)
assert(not collectgarbage('isrunning'))
print('generational edges ok')
