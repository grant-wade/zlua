-- outcome: error
-- message: instruction limit exceeded
-- max-instructions: 10000000
local n = ("a"):rep(1 << 20)
local c = load("local t, k = ...; t[k] = 1; for _ = 1, 200 do local r = t." .. n .. " end", "=c")
c({}, n:sub(1, 1 << 19) .. n:sub((1 << 19) + 1))
