-- outcome: error
-- message: instruction limit exceeded
local s = ("a,b\n"):rep(1 << 18)
while true do csv.read(s) end
