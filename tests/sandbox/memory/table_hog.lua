-- max-instructions: none
-- outcome: error
-- message: memory limit exceeded
local t = {} local i = 0 while true do i = i + 1 t[i] = {} end
