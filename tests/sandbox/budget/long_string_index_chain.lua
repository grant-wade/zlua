-- outcome: error
-- message: instruction limit exceeded
local a = ("7"):rep(1 << 20)
local b = ("7"):rep(1 << 19) .. ("7"):rep(1 << 19)
local t = {[a] = 1}
local p = setmetatable({}, {__index = t})
for _ = 1, 100 do local r = p[b] end
