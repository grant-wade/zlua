-- expect: pass
-- stage: runtime
-- feature: numbers
-- normalize: none

print(tonumber("0x"..string.rep("f", 13)..".0") == 2.0^(4*13) - 1)
print(tonumber("0x"..string.rep("f", 150)..".0") == 2.0^(4*150) - 1)
print(tonumber("0x"..string.rep("f", 300)..".0") == 2.0^(4*300) - 1)
print(tonumber("0x"..string.rep("f", 500)..".0") == 2.0^(4*500) - 1)
print(tonumber('0x3.' .. string.rep('0', 1000)) == 3)
print(tonumber('0x' .. string.rep('0', 1000) .. 'a') == 10)
print(tonumber('0x0.' .. string.rep('0', 500).."1") == 2.0^(-4*501))
print(tonumber('0xe03' .. string.rep('0', 1000) .. 'p-4000'))
print(tonumber('0x.' .. string.rep('0', 1000) .. '74p4004'))
print(load("return 0xe03" .. string.rep('0', 1000) .. "p-4000")())
print(0x1p4, 0x.8, 0xA.8p1, 0x1P-2, 0x.1p4, tonumber("0x1p2000000000"), tonumber("0x1p-2000000000"))
print(tonumber("0x"), tonumber("0x.p1"), tonumber("0x1p"), tonumber("0x1.2.3"), tonumber(" 0x1p+3 "), tonumber("-0x.8"))
print(math.type(0x10), math.type(0x1.0), 0xffffffffffffffff, 0x7fffffffffffffff)
print(string.format("%a", 0x1.8p3), 1e308 * 10, tonumber("0x" .. string.rep("f", 30)))
