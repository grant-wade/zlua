-- outcome: error
-- message: instruction limit exceeded
local w = setmetatable({}, {__mode = "k"})
local first = {} local k = first
for i = 1, 5000 do local n = {} w[k] = n k = n end
while true do collectgarbage() end
