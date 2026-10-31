-- max-memory: none
-- max-instructions: none
assert(load("if a then " .. ("elseif a then "):rep(100000) .. "end"))
