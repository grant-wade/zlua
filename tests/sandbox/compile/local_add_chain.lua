-- max-memory: none
-- max-instructions: none
assert(load('local a; return a' .. (' + a'):rep(200000) .. ''))
