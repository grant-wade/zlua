-- max-memory: none
-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local src = ("x=1 "):rep(1 << 20)
while true do load(src) end
