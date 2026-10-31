-- outcome: error
-- message: instruction limit exceeded
local s = ("x"):rep(16 << 20)
while true do local r = s:reverse() end
