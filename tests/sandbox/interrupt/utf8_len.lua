-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local s = ("x"):rep(16 << 20)
while true do utf8.len(s) end
