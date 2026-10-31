-- max-memory: none
-- max-instructions: none
assert(load('return a' .. (' + 1'):rep(200000) .. ''))
