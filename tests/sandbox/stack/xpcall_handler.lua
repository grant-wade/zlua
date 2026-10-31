-- max-memory: none
-- max-instructions: none
local function f() error("x") end
local function h(m) return xpcall(f, h) end
xpcall(f, h)
