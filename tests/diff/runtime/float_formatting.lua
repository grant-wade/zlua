-- expect: pass
-- stage: runtime
-- feature: float-formatting
-- normalize: none

-- tostring uses "%.15g", then "%.17g" when 15 digits do not read back as the
-- same float, and appends ".0" to integral results. NaN and "%a" are left
-- out: their spelling depends on the C library.

local values = {
  0.0, -0.0, 1.0, -1.0, 0.1, 0.5, 1 / 3, 2 / 3, 0.1 + 0.2, 100.0, 1e14, 1e15, 1e16,
  2^53, 2^63, -2^63, 1e100, 1e300, 1.7976931348623157e308, 2.2250738585072014e-308,
  5e-324, 4.9e-322, 1e-5, 1e-4, math.pi, -math.pi, 123456789012345.0,
  1234567890123456.0, 3.14159265358979, 1 / 0, -1 / 0,
}

for _, value in ipairs(values) do
  print(value, tostring(value), value .. "", #tostring(value))
end
io.write(1e15, " ", 2^63, " ", 1 / 3, " ", 1 / 0, " ", -0.0, "\n")

-- Finite numbers keep round-tripping through strings.
for _, value in ipairs(values) do
  if value == value and value ~= 1 / 0 and value ~= -1 / 0 then assert(tonumber(tostring(value)) == value) end
end
print(math.tointeger(2^53), math.tointeger(1e15), tonumber("1e15"), math.type(tonumber("1e15")))

local formats = {
  "%g", "%.3g", "%.17g", "%.0g", "%#g", "%#.3g", "%G", "%e", "%.0e", "%.3e", "%#.0e",
  "%E", "%.20e", "%f", "%.0f", "%.3f", "%#.0f", "%10.3g", "%-10.3g|", "%+g", "% g",
  "%010.3f", "%-+12.4e|", "%+012.3e", "%.99g",
}
local finite = {
  0.0, -0.0, 1.0, 0.1, 1 / 3, 1e15, 1e16, 2^53, 2^63, -2^63, math.pi, 123456789012345.0,
  5e-324, 2.2250738585072014e-308, 1e-5, 1e-4, 1e100, 1.7976931348623157e308,
  0.5, 1.5, 2.5, 0.125, 1e21, 123.456, 9.995, 0.0001234, 99.96, 1.005,
}
for _, fmt in ipairs(formats) do
  local out = {}
  for _, value in ipairs(finite) do out[#out + 1] = string.format(fmt, value) end
  print(fmt, table.concat(out, " "))
end
print(string.format("%.99f", 0.1))
print(string.format("%.99f", 1e308))
print(string.format("%.0f %.0f %.0f %.0e %.1f %.2f", 0.5, 1.5, 2.5, 25.0, 0.25, 1.005))
print(string.format("%g %g %g %g %#.10g", 100000, 1000000, 1e-4, 1e-5, 1.0))
print(string.format("%g %e %f %G %E", 1 / 0, -1 / 0, 1 / 0, 1 / 0, -1 / 0))
print(string.format("%5g|%-6f|%+e|%010g|% f", 1 / 0, -1 / 0, 1 / 0, 1 / 0, 1 / 0))
print(string.format("%d %x %5.2s %.14g %5.1f|", 3.0, 255.0, "abc", 2^63, 0.05))
