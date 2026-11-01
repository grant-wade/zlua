-- max-memory: none
-- max-instructions: none
assert(load('if a' .. (' and b'):rep(200000) .. ' then end'))
