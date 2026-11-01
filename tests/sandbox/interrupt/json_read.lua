-- max-memory: none
-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local s = "[" .. ("1,"):rep(1 << 20) .. "1]"
while true do json.read(s) end
