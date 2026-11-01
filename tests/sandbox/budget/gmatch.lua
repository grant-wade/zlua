-- min-stack: 1048576
-- outcome: error
-- message: instruction limit exceeded
local s = ("a"):rep(32)
for _ in s:gmatch(("a-"):rep(12) .. "b") do end
while true do end
