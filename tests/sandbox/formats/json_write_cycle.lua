-- max-memory: none
-- max-instructions: none
local t = {} t.a = t
assert(not pcall(json.write, t))
