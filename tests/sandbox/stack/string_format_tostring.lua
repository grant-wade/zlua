-- max-memory: none
-- max-instructions: none
local mt = {} mt.__tostring = function(t) return string.format("%s", t) end
assert(not pcall(tostring, setmetatable({}, mt)))
