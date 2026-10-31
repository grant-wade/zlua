-- outcome: error
-- message: instruction limit exceeded
local s = ("a=1\n"):rep(1) .. "b=[" .. ("1,"):rep(1 << 18) .. "1]"
while true do toml.read(s) end
