-- max-memory: none
-- max-instructions: none
local function f() return xpcall(f, f) end
f()
