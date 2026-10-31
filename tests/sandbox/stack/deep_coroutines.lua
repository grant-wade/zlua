-- max-memory: none
-- max-instructions: none
local c for i = 1, 20000 do local p = c c = coroutine.create(function() return p end) end
collectgarbage() collectgarbage()
