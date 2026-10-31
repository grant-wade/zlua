-- max-memory: none
-- max-instructions: none
assert(not load("return " .. ("- "):rep(2000000) .. "1"))
