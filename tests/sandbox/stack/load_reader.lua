-- max-memory: none
-- max-instructions: none
local function f() return load(f) end
pcall(f)
