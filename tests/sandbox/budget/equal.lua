-- outcome: error
-- message: instruction limit exceeded
local a = ("x"):rep(16 << 20) .. "a"
local b = ("x"):rep(16 << 20) .. "b"
while true do local r = a == b end
