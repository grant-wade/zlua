-- min-stack: 1048576
-- fault-sweep: true
-- max-memory: none
-- max-instructions: none
local str = ("abc"):rep(50) .. tostring(1.5) .. 1 .. 2.5
str:gsub("%w", {a = "1"}) str:gsub("b", function(m) return m:upper() end) str:find("c+") str:match("(a)(b)")
for w in str:gmatch("a") do end
string.format("%5d %s %q %f %x", 1, "s", "q", 2.5, 3)
string.pack("<i4s1", 1, "abc") string.unpack("<i4", "abcd") str:reverse() str:upper() str:lower() str:byte(1, 5) str:sub(2, 90)
string.split("a b c") string.rsplit("a,b", ",") string.strip("  x ")
utf8.char(228, 8364) utf8.len("äö") for p, c in utf8.codes("äö") do end utf8.codepoint("ä") utf8.offset("äö", 2)
