-- outcome: interrupted
-- max-instructions: none
-- max-memory: none
-- interrupt-ms: 100
-- latency-ms: 2000
local s = ("x=1 "):rep(1 << 16):rep(1 << 9)
return load(s)
