-- outcome: error
-- message: instruction limit exceeded
local t = table.create(100000) for i = 1, 100000 do t[i] = {} end
while true do collectgarbage("step") end
