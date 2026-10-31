-- max-memory: none
-- max-instructions: none
local function f() return ("x"):gsub("x", f) end
assert(not pcall(f))
