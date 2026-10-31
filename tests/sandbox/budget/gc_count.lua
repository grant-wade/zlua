-- outcome: error
-- message: instruction limit exceeded
local t = table.create(1000) for i = 1, 1000 do t[i] = coroutine.create(function() end) end
while true do collectgarbage("count") end
