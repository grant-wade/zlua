-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

collectgarbage('stop')
for _, value in ipairs({0, 1, 7, 19, 33, 70, 125, 333, 1000, 198400, 2147483647}) do
  collectgarbage('param', 'pause', value)
  print(collectgarbage('param', 'pause'))
end
local old = collectgarbage('param', 'pause')
assert(collectgarbage('param', 'pause', -10) == old)
assert(collectgarbage('param', 'pause', nil) == old)
assert(not pcall(collectgarbage, 'param', 'pause', 3.5))
assert(not pcall(collectgarbage, 'param', 'missing', 10))
assert(type(collectgarbage('step', nil)) == 'boolean')
assert(not collectgarbage('isrunning'))
collectgarbage('incremental')
for _, params in ipairs({{0,200}, {1,200}, {200,0}, {8,1}}) do
  collectgarbage('param', 'stepsize', params[1])
  collectgarbage('param', 'stepmul', params[2])
  assert(collectgarbage('step', 0))
  assert(collectgarbage('step', 2147483647))
end
print('gc params ok')
