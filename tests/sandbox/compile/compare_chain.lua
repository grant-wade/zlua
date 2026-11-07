-- max-memory: none
-- max-instructions: none
assert(load('return f' .. (' < 1'):rep(200000) .. ''))
