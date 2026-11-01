-- outcome: interrupted
-- max-instructions: none
-- max-memory: none
-- interrupt-ms: 100
-- latency-ms: 2000
local s = "[" .. ("1,"):rep(1 << 16):rep(1 << 9) .. "1]"
return json.read(s)
