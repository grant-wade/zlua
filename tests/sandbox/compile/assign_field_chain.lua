-- max-memory: none
-- max-instructions: none
assert(not load('f' .. ('.a'):rep(200000) .. ' = 1'))
