-- outcome: error
-- message: instruction limit exceeded
-- max-instructions: 10000000
local a = ("7"):rep(1 << 20)
local b = ("7"):rep(1 << 19) .. ("7"):rep(1 << 19)
local c = load('local k = ...; for _ = 1, 200 do if k == "' .. a .. '" then end end', "=c")
c(b)
