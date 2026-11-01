-- max-memory: none
-- max-instructions: none
local function f() host_call(f) end
assert(not pcall(f))
