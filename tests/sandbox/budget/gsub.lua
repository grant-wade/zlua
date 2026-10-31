-- outcome: error
-- message: instruction limit exceeded
local s = ("x"):rep(4 << 20)
while true do s:gsub("x", "") end
