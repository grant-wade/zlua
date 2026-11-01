-- outcome: error
-- message: instruction limit exceeded
local s = ("x"):rep(16 << 20)
while true do pcall(utf8.codepoint, s, 1, -1) end
