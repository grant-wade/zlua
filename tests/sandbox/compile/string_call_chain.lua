-- max-memory: none
-- max-instructions: none
assert(load('return f' .. (" 'x'"):rep(200000) .. ''))
