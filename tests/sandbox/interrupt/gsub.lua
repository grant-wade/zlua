-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local s = ("x"):rep(4 << 20)
while true do s:gsub("x", "") end
