-- expect: pass
-- stage: stdlib
-- feature: stdlib-string
-- normalize: none

local nan = 0 / 0
for _, value in ipairs({ nan, -nan, math.huge, -math.huge }) do
  print(tostring(value))
  for _, format in ipairs({ "%g", "%+g", "% g", "%08g", "%+08g", "%-8g", "%a", "%+a", "%G", "%E" }) do
    print(format, string.format(format, value))
  end
end
