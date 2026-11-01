-- max-memory: 10485760
-- max-instructions: none
local s = ("x"):rep(2 << 20)
local j = json.write({s})
for _ = 1, 40 do local r = json.read(j) end
