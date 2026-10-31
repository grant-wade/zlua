-- outcome: error
-- message: instruction limit exceeded
local s = ("x"):rep(1 << 16)
while true do pcall(string.byte, s, 1, -1) end
