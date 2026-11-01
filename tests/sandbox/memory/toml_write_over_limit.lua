-- outcome: error
-- message: memory limit exceeded
-- max-memory: 10485760
-- max-instructions: none
local s = ("x"):rep(6 << 20)
local r = toml.write({a = s})
