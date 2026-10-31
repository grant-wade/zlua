-- outcome: error
-- message: instruction limit exceeded
local s = ("x"):rep(1 << 12) local r = ("y"):rep(1 << 8)
while true do s:gsub("x", r) end
