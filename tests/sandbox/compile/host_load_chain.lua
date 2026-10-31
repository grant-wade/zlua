-- max-memory: none
-- max-instructions: none
assert(host_load("return f" .. ("()"):rep(200000)))
