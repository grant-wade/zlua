-- max-memory: none
-- max-instructions: none
assert(not pcall(toml.read, "a=" .. ("{b="):rep(2000000)))
