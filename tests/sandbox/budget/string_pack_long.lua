-- outcome: error
-- message: instruction limit exceeded
local f = ("b"):rep(1 << 18)
while true do pcall(string.pack, f) end
