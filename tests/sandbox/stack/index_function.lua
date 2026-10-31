-- max-memory: none
-- max-instructions: none
local mt = {} mt.__index = function(t, k) return t[k] end
assert(not pcall(function() return setmetatable({}, mt).x end))
