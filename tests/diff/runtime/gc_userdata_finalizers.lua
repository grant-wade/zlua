-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

-- A userdata gets the `__gc` of the metatable it has when it dies. Files are
-- registered when created, so a replaced metatable still finalizes them.
warn("@on")
local f = io.tmpfile()
debug.setmetatable(f, {__gc = function(u) print("udata gc", io.type(u), type(u)) end, __name = "X"})
f = nil
collectgarbage()
print("after 1")
do
  local f = io.tmpfile()
  debug.setmetatable(f, {__gc = function(u) print("resurrect"); SAVED = u end})
end
collectgarbage()
print(type(SAVED))
SAVED = nil
collectgarbage()
print("gone")
do
  local f = io.tmpfile()
  local mt = {}
  debug.setmetatable(f, mt)
  mt.__gc = function() print("never: set after") end
end
collectgarbage()
print("after 5")
do
  local f = io.tmpfile()
  debug.setmetatable(f, {__gc = function() error("udata boom", 0) end})
end
collectgarbage()
do
  local f = io.tmpfile()
  debug.setmetatable(f, {__gc = function(u) print("again 1"); debug.setmetatable(u, getmetatable(u)); SAVED2 = u end})
end
collectgarbage()
SAVED2 = nil
collectgarbage()
print("after 6")
local g = io.tmpfile()
debug.setmetatable(g, {__gc = function(u) print("udata at close") end})
KEEP = setmetatable({}, {__gc = function() print("table at close") end})
local h = io.tmpfile()
debug.setmetatable(h, {__gc = function(u) print("udata 2 at close") end})
debug.setmetatable(io.stdout, {__gc = function() print("stdout gc at close") end, __index = getmetatable(io.stdout).__index})
print("end")
