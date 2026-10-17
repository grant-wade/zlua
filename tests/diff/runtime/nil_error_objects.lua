-- expect: pass
-- stage: runtime
-- feature: errors
-- normalize: none

-- Message handlers see a nil error object; where an error is caught without
-- one, Lua substitutes "<no error object>".
print(xpcall(function() error(nil) end, function(e) return type(e) end))
print(xpcall(function() error() end, function(e) return select("#", e), e end))
print(xpcall(error, function(e) return type(e) end, nil))
print(xpcall(function() error(nil) end, function() return nil end))
print(xpcall(function() error(nil) end, function() end))
print(xpcall(function() error(nil) end, function(e) error(nil) end))
print(pcall(error))
print(pcall(error, nil))
print(pcall(error, nil, 2))
print(select("#", pcall(error)))
print(pcall(pcall, error))
print(select(2, pcall(error)) == "<no error object>")
print(pcall(assert, false, nil))

print(coroutine.resume(coroutine.create(function() error(nil) end)))
print(pcall(coroutine.wrap(function() error(nil) end)))
print(xpcall(coroutine.wrap(function() error(nil) end), function(e) return type(e) end))
local co = coroutine.create(function() error(nil) end)
coroutine.resume(co)
print(coroutine.close(co))

print(pcall(function()
  local x <close> = setmetatable({}, { __close = function(_, e) print("close sees", e) end })
  error(nil)
end))
print(pcall(function()
  local x <close> = setmetatable({}, { __close = function() error(nil) end })
end))
print(xpcall(function()
  local x <close> = setmetatable({}, { __close = function() error(nil) end })
end, function(e) return type(e) end))
print(xpcall(function()
  local x <close> = setmetatable({}, { __close = function() error(nil) end })
  error("first")
end, function(e) return type(e) end))
co = coroutine.create(function()
  local x <close> = setmetatable({}, { __close = function() error(nil) end })
  coroutine.yield()
end)
coroutine.resume(co)
print(coroutine.close(co))

local t = {}
print(pcall(load, function() error(nil) end))
print(select(3, pcall(load, function() error(t) end)) == t)
