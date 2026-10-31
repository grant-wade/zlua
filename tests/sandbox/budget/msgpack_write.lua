-- outcome: error
-- message: instruction limit exceeded
local t = table.create(30000) for i = 1, 30000 do t[i] = i end
while true do msgpack.write(t) end
