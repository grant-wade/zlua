-- expect: pass
-- stage: runtime
-- feature: string-arithmetic
-- normalize: none

-- Strings take part in arithmetic through the string library's metamethods,
-- but there are none for bitwise operators.

local function check(fn)
  local ok, err = pcall(fn)
  if ok then
    print(true, err)
  else
    print(false, (tostring(err):gsub("[^%s]*:(%d+): ", "chunk:%1: ")))
  end
end

check(function() return "3" | 0 end)
check(function() local s = "3" return s & 1 end)
check(function() return ~"3" end)
check(function() local t = { x = "7" } return t.x << 1 end)
check(function() return 1 >> "2" end)
check(function() return "3.0" ~ 1 end)
check(function() return 1.5 | "x" end)
check(function() return -"x" end)
check(function() return -"2", -"2.0", -"0x10", math.type(-"2") end)
check(function() return "10" + 1, "0x10" * 1, " 5 " // 2, "3" ^ 2, "7" % "-3", "1e1" - 0 end)
check(function() return "abc" + 1 end)
check(function() local s = "abc" return 1 + s end)
check(function() return {} + "1" end)
check(function() return "1" + setmetatable({}, { __name = "Thing" }) end)
check(function() return "5" // 0 end)
check(function() return "5" % 0 end)
check(function() return 5 // "0" end)
check(function() return 3 % -"0" end)
check(function() return 1 // 0 end)
check(function() return 1 % 0 end)

-- Numbers without an integer value name their origin like Lua's varinfo.
check(function() return math.huge | 0 end)
check(function() return (1 / 0) | 0 end)
check(function() local x = 1.5 return x | 0 end)
check(function() return 2^63 | 0 end)
check(function() return 1.5 // 0 | 1 end)
check(function() return math.pi & 1 end)
check(function() local y = 2.5 return 1 | y end)
check(function() local t = { f = 1.5 } return t.f ~ 1 end)
check(function() return ~1.5 end)
check(function() local z = 0.5 return ~z end)
check(function() return 2^63 | 1.5 end)
check(function() return 1.5 | {} end)
check(function() return {} | 1.5 end)
check(function() return ~{} end)
check(function() local t = {} return t.x | 1 end)
check(function() return 3 | 1.0, 3.0 | 1, 7 // 2.0 end)
