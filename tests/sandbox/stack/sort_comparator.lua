-- max-memory: none
-- max-instructions: none
local function f() table.sort({1, 2, 3}, function() f() return false end) end
assert(not pcall(f))
