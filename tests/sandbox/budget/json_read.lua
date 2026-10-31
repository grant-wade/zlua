-- outcome: error
-- message: instruction limit exceeded
local s = "[" .. ("1,"):rep(1 << 20) .. "1]"
while true do json.read(s) end
