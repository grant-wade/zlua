-- expect: pass
-- stage: runtime
-- feature: constant-folding
-- normalize: paths

local function show(label, value)
  print(label, math.type(value) or type(value), value)
end

local function err(f)
  local ok, message = pcall(f)
  message = tostring(message):gsub("^.-constant_folding%.lua:", "constant_folding.lua:")
  message = message:gsub("^zlua:", "constant_folding.lua:")
  print(ok, message)
end

-- Arithmetic keeps integer and float result types.
show("pow mul add", 2^10 * 3 + 1)
show("int add", 1 + 2)
show("int sub", 10 - 20)
show("int mul", 6 * 7)
show("mixed add", 1 + 2.0)
show("div ints", 7 / 2)
show("div exact", 8 / 2)
show("idiv ints", 7 // 2)
show("idiv neg", -7 // 2)
show("idiv float", 7.5 // 2)
show("mod ints", 7 % 3)
show("mod neg", -7 % 3)
show("mod neg divisor", 7 % -3)
show("mod float", 5.5 % 2)
show("mod float neg", -5.5 % 2)
show("pow ints", 2^2)
show("pow frac", 4^0.5)
show("unary minus", -(3))
show("unary minus float", -(2.5))
show("nested", ((1 + 2) * (3 - 4)) // 2)
show("grouped", (2) * (3))

-- Integer overflow wraps.
show("max + 1", 9223372036854775807 + 1)
show("min - 1", -9223372036854775807 - 2)
show("max * 2", 9223372036854775807 * 2)
show("mininteger", -9223372036854775807 - 1)
show("mininteger // -1", (-9223372036854775807 - 1) // -1)
show("mininteger % -1", (-9223372036854775807 - 1) % -1)
show("-mininteger", -(-9223372036854775807 - 1))
print("overflowing literal", math.type(-9223372036854775808), -9223372036854775808 == -2^63)
show("hex wrap", 0xffffffffffffffff + 1)
print(9223372036854775807 + 1 == math.mininteger)
print((-9223372036854775807 - 1) // -1 == math.mininteger)

-- Division and modulo by zero are left to run time.
err(function() return 1 // 0 end)
err(function() return 1 % 0 end)
err(function() local x = 5 return x // (2 - 2) end)
show("1/0", 1 / 0)
show("-1/0", -1 / 0)
show("1/0.0", 1 / 0.0)
show("3 // 0.0", 3 // 0.0)
show("-3 // 0.0", -3 // 0.0)
show("1 % 0.0 is nan", (1 % 0.0) ~= (1 % 0.0))
show("1 % -0.0 is nan", (1 % -0.0) ~= (1 % -0.0))
show("1 / -0.0", 1 / -0.0)
show("0.0/0.0 is nan", (0.0 / 0.0) ~= (0.0 / 0.0))
show("huge", 1e308 * 10)
show("-huge", -1e308 * 10)
show("huge literal", 1e999)
show("mod huge", 5 % 1e999)
show("neg mod huge", -5 % 1e999)

-- Zero and negative zero floats.
show("-0.0", -0.0)
show("0.0 * -1", 0.0 * -1)
show("1.0 - 1.0", 1.0 - 1.0)
show("-0", -0)
print(1 / (-0.0) < 0, 1 / (0.0 * -1) < 0, 1 / (-(0.0)) < 0)
show("tiny product", 1e-300 * 1e-300)
show("neg tiny product", -1e-300 * 1e-300)
print(1 / (-1e-300 * 1e-300))

-- Bitwise operators need exact integer representations.
show("band", 0xF0 & 0x3C)
show("bor", 0xF0 | 0x0F)
show("bxor", 0xFF ~ 0x0F)
show("bnot", ~0)
show("bnot float", ~5.0)
show("float bor", 3.0 | 0)
show("float shl", 1.0 << 4)
show("2^53 band", 2^53 | 0)
show("shl 63", 1 << 63)
show("shl 64", 1 << 64)
show("shl 100", 1 << 100)
show("shr 64", -1 >> 64)
show("shr 63", -1 >> 63)
show("shr 1", -1 >> 1)
show("shl negative", 8 << -2)
show("shr negative", 1 >> -3)
show("shr mininteger", 1 >> (-9223372036854775807 - 1))
show("shl mininteger", 1 << (-9223372036854775807 - 1))
err(function() return 1.5 | 0 end)
err(function() return 1 & 2.5 end)
err(function() return ~1.5 end)
err(function() return 1e100 | 0 end)
err(function() return 2^63 | 0 end)
err(function() return 1 << 0.5 end)

-- Strings are not folded and still coerce at run time.
show("string arith", "10" + 1)
show("string concat number", 1 .. 2)
err(function() return "a" + 1 end)
err(function() return {} + (1 + 2) end)
err(function() return (1 + 2) + {} end)
err(function() return 2 ^ nil end)

-- Folding inside larger expressions and contexts.
local t = {}
t[1 + 1] = "two"
t[2.0 * 1] = "float key"
print(t[2], #t)
local x = 10
print(x + 2 * 3, x * (2 - 3), (1 + 1) .. "", -x + -(-1))
for i = 1 + 0, 2 * 2, 4 // 2 do io.write(i, " ") end
print()
if 2 * 3 == 6 then print("folded condition") end
print(0.1 + 0.2 == 0.30000000000000004, 1 / 3 == 0.33333333333333331, 2^0.5 == 1.4142135623730951)
print(string.format("%d %d", 3 * 4, 7 // 2), math.type(3 * 4.0))
print(1e15 + 0.5, 2^53 + 1, 2^-1074 > 0)
print(math.ult(1 << 63, 1), 5 // 0.5, 7.0 % 2.5)

-- Folded results match the same operations performed at run time.
local function same(a, b)
  if a ~= a then return b ~= b end
  return a == b and math.type(a) == math.type(b) and 1 / a == 1 / b
end
local i0, i1, i2, i3, i7, imax, imin = 0, 1, 2, 3, 7, math.maxinteger, math.mininteger
local f05, f1, f25, fhuge = 0.5, 1.0, 2.5, 1e308
print(same(7 // 2, i7 // i2), same(-7 % 3, -i7 % i3), same(7 / 2, i7 / i2))
print(same(2^10 * 3 + 1, i2^10 * i3 + i1), same(1e308 * 10, fhuge * 10))
print(same(9223372036854775807 + 1, imax + i1), same(-(-9223372036854775807 - 1), -imin))
print(same(2.5 % 0.5, f25 % f05), same(-2.5 // 0.5, -f25 // f05), same(1 / 3, i1 / i3))
print(same(1 << 63, i1 << 63), same(-1 >> 1, -i1 >> i1), same(~5.0, ~(f1 * 5)))
print(same(3 % -2, i3 % -i2), same(3.0 % -2, (f1 * 3) % -i2), same(2^-1, i2^-i1))
print(same(5 % 1e999, 5 % (fhuge * 10)), same(-5 % 1e999, -5 % (fhuge * 10)))
