-- max-memory: none
-- max-instructions: none
local function f() return pcall(pcall, f) end
f()
