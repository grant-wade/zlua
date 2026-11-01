-- outcome: error
-- message: instruction limit exceeded
while true do local s = ("x"):rep(16 << 20) end
