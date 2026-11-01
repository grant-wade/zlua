-- outcome: error
-- message: instruction limit exceeded
local src = ("x=1 "):rep(1 << 16)
while true do load(src) end
