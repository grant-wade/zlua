-- outcome: error
-- message: instruction limit exceeded
local s = (" "):rep(1 << 22)
while true do string.strip(s) end
