-- outcome: error
-- message: instruction limit exceeded
-- max-instructions: 10000000
local a = ("7"):rep(1 << 20)
local b = ("7"):rep(1 << 19) .. ("7"):rep(1 << 19)
local c = load('local t, k = ...; t[k] = 1; for _ = 1, 200 do t["' .. a .. '"] = 2 end', "=c")
c({}, b)
