-- outcome: error
-- message: instruction limit exceeded
local n = 0
while true do pcall(function() local c <close> = setmetatable({}, {__close = function() while true do n = n + 1 end end}) while true do end end) end
