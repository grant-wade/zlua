-- min-stack: 1048576
-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local s = ("a"):rep(32)
while true do s:find(("a-"):rep(12) .. "b") end
