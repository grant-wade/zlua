-- max-memory: 10485760
-- max-instructions: none
local s = ("x"):rep(1 << 20)
local j = toml.write({a = s})
for _ = 1, 40 do local r = toml.read(j) end
