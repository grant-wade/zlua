-- outcome: error
-- message: instruction limit exceeded
local s = ("x"):rep(1 << 22)
while true do string.format("%s", s) end
