-- max-memory: none
-- max-instructions: none
assert(load('return 1' .. (' + a'):rep(200000) .. ''))
