-- fault-sweep: true
-- max-memory: none
-- max-instructions: none
local o = setmetatable({}, {__close = function() end})
local co = coroutine.wrap(function(a) local b <close> = o for i = 1, 5 do a = coroutine.yield(a) end return a end)
for i = 1, 5 do co(i) end
coroutine.close(coroutine.create(function() end))
local c2 = coroutine.create(function() local z <close> = o coroutine.yield(1) end)
coroutine.resume(c2) coroutine.close(c2)
coroutine.wrap(pcall)(error, "x")
