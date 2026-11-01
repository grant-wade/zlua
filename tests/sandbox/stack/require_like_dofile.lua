-- max-memory: none
-- max-instructions: none
local function f() return load("return ...")(f()) end
assert(not pcall(f))
