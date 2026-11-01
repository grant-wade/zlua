-- max-memory: none
-- max-instructions: none
local function f() for _ in ("x"):gmatch("x") do f() end end
assert(not pcall(f))
