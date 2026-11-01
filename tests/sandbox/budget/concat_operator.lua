-- outcome: error
-- message: instruction limit exceeded
local s = ("x"):rep(8 << 20)
while true do local r = s .. "y" end
