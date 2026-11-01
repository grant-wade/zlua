-- max-memory: none
-- max-instructions: none
local mt = {} mt.__index = function(t, i) return table.concat(t, ",", 1, 1) end
assert(not pcall(table.concat, setmetatable({}, mt), ",", 1, 1))
