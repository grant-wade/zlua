-- max-memory: none
-- max-instructions: none
local function f() setmetatable({}, {__gc = f}) collectgarbage() end
pcall(f)
