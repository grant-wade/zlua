-- max-memory: none
-- max-instructions: none
assert(load('if a' .. (' or b'):rep(200000) .. ' then end'))
