-- outcome: error
-- message: output limit exceeded
-- max-output: 1048576
-- max-instructions: none
warn("@on")
local s = ("x"):rep(1 << 20)
while true do warn(s) end
