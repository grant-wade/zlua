-- max-memory: none
-- max-instructions: none
pcall(toml.read, "a" .. (".a"):rep(1000000) .. "=1")
