-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none
-- gc-stress: skip
-- reason: finalizer order across separate collections depends on collection timing

-- Objects that die together are finalized newest first, tables and
-- userdata alike.
local objects = {}
objects[1] = setmetatable({}, {__gc = function() print("t1") end})
objects[2] = io.tmpfile()
debug.setmetatable(objects[2], {__gc = function() print("u") end})
objects[3] = setmetatable({}, {__gc = function() print("t2") end})
objects = nil
collectgarbage()
print("after 2")
objects = {}
objects[1] = io.tmpfile()
objects[2] = setmetatable({}, {__gc = function() print("t") end})
debug.setmetatable(objects[1], {__gc = function() print("u late") end})
objects = nil
collectgarbage()
print("after 3")
