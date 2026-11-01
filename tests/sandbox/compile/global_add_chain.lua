-- max-memory: none
-- max-instructions: none
assert(not load('return 1' .. (' + a'):rep(200000) .. ''))
