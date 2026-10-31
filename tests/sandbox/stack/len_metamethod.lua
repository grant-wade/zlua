-- max-memory: none
-- max-instructions: none
local mt = {} mt.__len = function(a) return #a end
assert(not pcall(function() return #setmetatable({}, mt) end))
