-- max-memory: 10485760
-- max-instructions: none
local p = ("x"):rep(1 << 16)
local a = {}
for i = 1, 48 do a[i] = p end
for _ = 1, 40 do local r = table.concat(a) end
