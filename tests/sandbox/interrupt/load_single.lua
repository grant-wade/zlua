-- outcome: interrupted
-- max-instructions: none
-- max-memory: none
-- interrupt-ms: 1500
-- latency-ms: 3000
local s = ("x=1 "):rep(1 << 16):rep(1 << 11)
return load(s)
