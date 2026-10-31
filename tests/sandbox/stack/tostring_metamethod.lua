-- max-memory: none
-- max-instructions: none
local mt = {} mt.__tostring = function(t) return tostring(t) end
assert(not pcall(tostring, setmetatable({}, mt)))
