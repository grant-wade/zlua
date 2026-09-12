-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

collectgarbage('stop')
-- Establish minor mode even if a stress runner started a major cycle before
-- this chunk stopped automatic collection.
collectgarbage('incremental')
collectgarbage('generational')
local weak = setmetatable({}, {__mode = 'kv'})
collectgarbage()
for i = 1, 3 do
  weak[1] = {i}
  collectgarbage('step')
  assert(weak[1] == nil)
  collectgarbage('step')
end

-- A zero minormajor parameter disables the transition even as survivors grow.
collectgarbage('param', 'minormajor', 0)
local live = {}
for i = 1, 100 do
  live[i] = {i}
  weak[1] = {i}
  collectgarbage('step')
  assert(weak[1] == nil)
end
assert(live[100][1] == 100)
print('full generational collection ok')
