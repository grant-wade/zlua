-- stdlib: full
local mt = debug.getmetatable(res)
pcall(mt.__gc, res) pcall(mt.__gc, res) pcall(mt.__gc, res)
