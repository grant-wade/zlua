-- max-memory: none
-- max-instructions: none
assert(not load(("function f() "):rep(100000)))
