-- outcome: error
-- message: instruction limit exceeded
local s = ("x"):rep(16 << 20)
while true do s:find("y", 1, true) end
