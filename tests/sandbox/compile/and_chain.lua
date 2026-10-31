-- max-memory: none
-- max-instructions: none
assert(load('return f' .. (' and g'):rep(200000) .. ''))
