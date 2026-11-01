-- max-memory: none
-- max-instructions: none
assert(load('return f' .. ('()'):rep(200000) .. ''))
