-- max-memory: none
-- max-instructions: none
local mt = {} mt.__pairs = function(t) return pairs(t) end
assert(not pcall(pairs, setmetatable({}, mt)))
