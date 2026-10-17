-- expect: pass
-- stage: stdlib
-- feature: stdlib-string
-- normalize: none

local nan = 0 / 0
for _, value in ipairs({ nan, -nan, math.huge, -math.huge }) do
  print(tostring(value))
  for _, format in ipairs({ "%g", "%+g", "% g", "%08g", "%+08g", "%-8g", "%a", "%+a", "%A", "%G", "%E" }) do
    print(format, pcall(string.format, format, value))
  end
end

for _, format in ipairs({ "%a", "%A", "%+a", "% a", "%08a", "%-8a", "%#a", "%.3a", "%+A", "%08A", "%.3A" }) do
  for _, value in ipairs({ 0.0, -0.0, 1.5, -1.5 }) do
    print(format, value, pcall(string.format, format, value))
  end
end
