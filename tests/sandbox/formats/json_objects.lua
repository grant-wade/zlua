-- max-memory: none
-- max-instructions: none
assert(not pcall(json.read, ('{"a":'):rep(2000000)))
