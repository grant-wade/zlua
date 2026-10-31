-- max-memory: none
-- max-instructions: none
local mt = {} mt.__newindex = function(t, k, v) t[k] = v end
assert(not pcall(function() setmetatable({}, mt).x = 1 end))
