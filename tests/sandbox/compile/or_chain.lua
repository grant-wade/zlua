-- max-memory: none
-- max-instructions: none
assert(load('return f' .. (' or 1'):rep(200000) .. ''))
