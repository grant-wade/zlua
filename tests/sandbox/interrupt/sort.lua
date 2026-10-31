-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local t = table.create(30000) for i = 1, 30000 do t[i] = i end
while true do table.sort(t) end
