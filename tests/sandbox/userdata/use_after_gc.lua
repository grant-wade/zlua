-- stdlib: full
local mt = debug.getmetatable(res)
assert(res:value() == 0)
mt.__gc(res)
assert(not pcall(function() return res:value() end))
assert(res2:value() == 1)
