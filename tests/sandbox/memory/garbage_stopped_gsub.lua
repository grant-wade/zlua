-- max-memory: 10485760
-- max-instructions: none
collectgarbage("stop")
local s = ("x"):rep(2 << 20)
for _ = 1, 40 do local r = s:gsub("^x", "y") end
