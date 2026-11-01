-- max-memory: none
-- max-instructions: none
local t = {} for i = 1, 100000 do t = setmetatable({}, {__call = t}) end
assert(not pcall(t))
