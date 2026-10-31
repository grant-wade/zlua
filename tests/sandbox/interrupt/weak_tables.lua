-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local w = setmetatable({}, {__mode = "k"}) local k = {} for i = 1, 20000 do local n = {} w[k] = n k = n end
while true do collectgarbage() end
