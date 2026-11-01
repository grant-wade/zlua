-- max-memory: none
-- max-instructions: none
local mt = {} mt.__concat = function(a, b) return a .. b end
assert(not pcall(function() return setmetatable({}, mt) .. "x" end))
