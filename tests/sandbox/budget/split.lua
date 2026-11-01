-- outcome: error
-- message: instruction limit exceeded
local s = ("x "):rep(1 << 16)
while true do string.split(s) end
