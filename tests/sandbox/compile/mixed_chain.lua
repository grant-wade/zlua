-- max-memory: none
-- max-instructions: none
assert(not load('return f' .. ('().a'):rep(200000) .. ''))
