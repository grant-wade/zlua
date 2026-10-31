-- outcome: error
-- message: output limit exceeded
-- max-output: 1048576
-- max-instructions: none
local s = ("x"):rep(1 << 20)
while true do pcall(print, s) end
