-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

-- Closing the state calls each finalizer still waiting in the queue once.
local ran = 0
local mt = { __gc = function()
  ran = ran + 1
  print("gc", ran)
end }
local live = debug.setmetatable(io.tmpfile(), mt)
local objects = {}
objects[1] = setmetatable({}, mt)
objects[2] = debug.setmetatable(io.tmpfile(), mt)
objects[3] = debug.setmetatable(io.tmpfile(), mt)
objects[4] = setmetatable({}, mt)
objects[5] = debug.setmetatable(io.tmpfile(), mt)
objects = nil
collectgarbage("incremental")
repeat collectgarbage("step") until ran > 0
