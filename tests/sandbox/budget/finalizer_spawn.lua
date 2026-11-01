-- max-instructions: none
-- call-instructions: 100000
local function spawn() setmetatable({}, {__gc = spawn}) end
spawn()
