-- max-memory: none
-- max-instructions: none
local t = {} for i = 1, 400000 do t = setmetatable({}, t) end
collectgarbage() collectgarbage()
