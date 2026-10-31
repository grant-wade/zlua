-- max-memory: none
-- max-instructions: none
local function f() local ok, err = coroutine.resume(coroutine.create(f)) assert(ok, err) end
assert(not pcall(f))
