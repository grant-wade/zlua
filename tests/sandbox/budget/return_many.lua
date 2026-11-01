-- outcome: error
-- message: instruction limit exceeded
local t = table.create(100000) for i = 1, 100000 do t[i] = i end
local function g(...) return ... end
local function f(...) while true do g(...) end end
f(table.unpack(t))
