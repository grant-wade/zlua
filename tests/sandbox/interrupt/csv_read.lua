-- max-memory: none
-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local s = ("a,b\n"):rep(1 << 16)
while true do csv.read(s) end
