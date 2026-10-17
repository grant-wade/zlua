-- expect: pass
-- stage: stdlib
-- feature: warn
-- normalize: none

-- Warnings start off in the standalone interpreter; "@on" and "@off"
-- switch them and other control messages are ignored.
warn("not shown")
warn("@on")
warn("one")
warn("a", "b", "c")
warn("@o", "n")
warn("@unknown")
warn("")
warn(1, 2.5)
print(warn("returns nothing"))
print(pcall(warn))
print(pcall(warn, "a", {}))
print(pcall(warn, "a", nil))
print(pcall(warn, nil))
warn("@off")
warn("hidden", "too")
warn("@on")

-- Errors in finalizers become warnings, during collection and at close.
setmetatable({}, { __gc = function() error("collected", 0) end })
collectgarbage()
setmetatable({}, { __gc = function() error({}) end })
collectgarbage()
setmetatable({}, { __gc = function() error(nil) end })
collectgarbage()
setmetatable({}, { __gc = function() error(42) end })
collectgarbage()
print(pcall(function()
  setmetatable({}, { __gc = function() error("inside pcall", 0) end })
  collectgarbage()
  return "after"
end))
KEEP = setmetatable({}, { __gc = function() error("at close", 0) end })
print("end")
