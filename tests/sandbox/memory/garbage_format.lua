-- max-memory: 10485760
-- max-instructions: none
local s = ("x"):rep(2 << 20)
for _ = 1, 40 do local r = string.format("%s", s) end
