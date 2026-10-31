-- outcome: error
-- message: instruction limit exceeded
local a = ("x"):rep(1 << 20) .. "a"
local b = ("x"):rep(1 << 20) .. "b"
for _ = 1, 100 do local r = a == b end
