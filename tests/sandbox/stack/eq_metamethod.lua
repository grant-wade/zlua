-- max-memory: none
-- max-instructions: none
local mt = {} mt.__eq = function(a, b) return a == b end
assert(not pcall(function() return setmetatable({}, mt) == setmetatable({}, mt) end))
