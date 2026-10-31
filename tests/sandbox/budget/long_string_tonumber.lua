-- outcome: error
-- message: instruction limit exceeded
local n = (" "):rep(1 << 20) .. "1"
for _ = 1, 100 do tonumber(n) end
