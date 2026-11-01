-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
local s = ("a=1\n"):rep(1) .. "b=[" .. ("1,"):rep(1 << 18) .. "1]"
while true do toml.read(s) end
