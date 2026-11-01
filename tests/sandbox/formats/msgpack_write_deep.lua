-- max-memory: none
-- max-instructions: none
local t = {} for i = 1, 500000 do t = {a = t} end
assert(not pcall(msgpack.write, t))
