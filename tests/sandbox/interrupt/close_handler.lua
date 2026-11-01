-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local n = 0
while true do pcall(function() local c <close> = setmetatable({}, {__close = function() while true do n = n + 1 end end}) while true do end end) end
