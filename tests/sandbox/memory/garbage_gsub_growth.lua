-- max-memory: 10485760
-- max-instructions: none
local s = ("x"):rep(3 << 10)
local f = ("y"):rep(1 << 10)
for _ = 1, 40 do local r = s:gsub("x", f) end
