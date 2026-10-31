-- max-memory: none
-- max-instructions: none
local function f() local c <close> = setmetatable({}, {__close = function() f() end}) end
assert(not pcall(f))
