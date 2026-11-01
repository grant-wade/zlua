-- min-stack: 1048576
-- outcome: error
-- message: instruction limit exceeded
local s = ("a"):rep(32)
while true do s:find(("a-"):rep(12) .. "b") end
