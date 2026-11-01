-- max-memory: none
-- max-instructions: none
local t = setmetatable({}, {__tostring = tostring})
assert(not pcall(tostring, t))
