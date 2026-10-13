-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

-- Closing the state at exit calls every pending finalizer, newest first.
local keep = {}
local function gc(name, extra)
  local object = setmetatable({}, { __gc = function(o)
    print("gc", name)
    if extra then extra(o) end
  end })
  keep[#keep + 1] = object
  return object
end

local f = io.tmpfile()
gc("a", function() NEW = gc("created while closing") end)
gc("b", function() error("ignored") end)
gc("c", function(o) print(io.type(f), f:write("x") == f); SAVED = o; setmetatable(o, getmetatable(o)) end)
gc("d", function() print(collectgarbage(), collectgarbage("count"), collectgarbage("isrunning")) end)
gc("e", function() print(pcall(coroutine.yield)) end)
local g = io.tmpfile()
gc("h", function() print(io.type(g), io.type(f)) end)
keep[#keep + 1] = setmetatable({}, { __gc = 0 })
local co = coroutine.wrap(function()
  local x <close> = setmetatable({}, { __close = function() print("never closed") end })
  coroutine.yield()
end)
co()
local x <close> = setmetatable({}, { __close = function() print("chunk close") end })
print("end of chunk")
