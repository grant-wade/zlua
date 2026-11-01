-- max-memory: none
-- max-instructions: none
assert(not load('return f' .. (':m()'):rep(200000) .. ''))
