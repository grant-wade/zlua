-- stdlib: full
debug.setmetatable(res, debug.getmetatable(other))
assert(not pcall(function() return res:get() end))
debug.setmetatable(other, nil)
assert(not pcall(function() return other:get() end))
