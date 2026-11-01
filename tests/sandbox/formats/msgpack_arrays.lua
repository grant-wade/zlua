-- max-memory: none
-- max-instructions: none
assert(not pcall(msgpack.read, ("\x91"):rep(2000000)))
