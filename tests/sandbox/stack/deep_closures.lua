-- max-memory: none
-- max-instructions: none
local f for i = 1, 300000 do local p = f f = function() return p end end
collectgarbage() collectgarbage()
