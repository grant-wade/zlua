-- max-memory: 10485760
-- max-instructions: none
local s = ("x"):rep(1 << 20)
for _ = 1, 40 do local r = csv.write({{a = s}}) end
