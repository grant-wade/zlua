-- max-memory: none
-- max-instructions: none
local t = {} t.a = t
assert(not pcall(toml.write, t))
