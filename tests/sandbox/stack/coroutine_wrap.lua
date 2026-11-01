-- max-memory: none
-- max-instructions: none
local function f() return coroutine.wrap(f)() end
assert(not pcall(f))
