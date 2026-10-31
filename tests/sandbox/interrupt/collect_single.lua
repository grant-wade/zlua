-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
-- max-memory: none
local t = table.create(2000000) for i = 1, 2000000 do t[i] = {} end
while true do collectgarbage() end
