-- outcome: error
-- message: instruction limit exceeded
local f = load(("x=1 "):rep(1 << 14))
while true do string.dump(f) end
