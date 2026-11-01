-- max-instructions: none
-- outcome: error
-- message: memory limit exceeded
local t = {} while true do t[#t + 1] = ("x"):rep(1 << 20) .. #t end
