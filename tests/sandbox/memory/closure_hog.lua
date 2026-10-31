-- max-instructions: none
-- outcome: error
-- message: memory limit exceeded
local t = {} while true do local n = #t t[n + 1] = function() return n end end
