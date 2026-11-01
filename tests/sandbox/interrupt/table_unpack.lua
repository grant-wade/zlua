-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local t = table.create(100000) for i = 1, 100000 do t[i] = i end
while true do select("#", table.unpack(t)) end
