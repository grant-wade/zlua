-- max-memory: none
-- max-instructions: none
assert(not load('return f' .. ('[1]'):rep(200000) .. ''))
