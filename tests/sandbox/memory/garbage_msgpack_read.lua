-- max-memory: 10485760
-- max-instructions: none
local s = ("x"):rep(2 << 20)
local j = msgpack.write({s})
for _ = 1, 40 do local r = msgpack.read(j) end
