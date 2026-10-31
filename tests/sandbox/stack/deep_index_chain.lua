-- max-memory: none
-- max-instructions: none
local t = {} for i = 1, 400000 do t = setmetatable({}, {__index = t}) end
assert(not pcall(function() return t.x end))
