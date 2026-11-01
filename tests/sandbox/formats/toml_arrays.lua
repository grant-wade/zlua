-- max-memory: none
-- max-instructions: none
assert(not pcall(toml.read, "a=" .. ("["):rep(2000000)))
