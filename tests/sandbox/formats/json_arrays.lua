-- max-memory: none
-- max-instructions: none
assert(not pcall(json.read, ("["):rep(2000000)))
