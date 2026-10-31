-- stdlib: full
local keep
local mt = debug.getmetatable(res)
local original = mt.__gc
mt.__gc = function(u) keep = u return original(u) end
res, res2 = nil, nil
collectgarbage() collectgarbage()
assert(keep)
assert(not pcall(function() return keep:value() end))
