-- outcome: error
-- message: instruction limit exceeded
local t = table.create(100000) for i = 1, 100000 do t[i] = i end
local co = coroutine.wrap(function(...) while true do coroutine.yield(...) end end)
while true do co(table.unpack(t, 1, 1000)) end
