-- max-memory: none
-- max-instructions: none
assert(load('return 1' .. (' + 1'):rep(200000) .. ''))
