-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

collectgarbage('incremental')
collectgarbage('stop')
collectgarbage('param', 'stepsize', 8)
collectgarbage('param', 'stepmul', 100)
local root = { {}, {}, {} }
local weak = setmetatable({}, {__mode='v'})
for i=1,500 do
  root[1].child = { i, string.rep('x', 100) }
  root[2][root[1].child] = root[1].child
  local value = root[1].child
  root[3] = function() return value end
  weak[i] = value
  collectgarbage('step', 0)
  assert(root[1].child[1] == i and root[3]()[1] == i)
  if i % 10 == 0 then root[2] = {} end
end
collectgarbage('collect')
assert(root[1].child[1] == 500)
collectgarbage('generational')
for i=1,100 do
  root[1].child = {i}
  collectgarbage('step', 0)
  assert(root[1].child[1] == i)
end
print('gc mutations ok')
