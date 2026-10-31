local floats = { 2.0, 0.5, -0.0, 1e300, -1e300, 2^63, 1e15, 999999999999999.0, 1e-7, 1.5e-300 }

for _, value in ipairs(floats) do
  local text = json.write(value)
  local back = json.read(text)
  print(text, math.type(back), back == value)
end

print(json.write(3), math.type(json.read(json.write(3))))
print(json.write({ 1, 2.0, { value = 2^63 } }))

for _, value in ipairs(floats) do
  local text = toml.write({ value = value })
  local back = toml.read(text).value
  print((text:gsub("\n$", "")), math.type(back), back == value)
end

print((toml.write({ whole = 3 }):gsub("\n$", "")), math.type(toml.read(toml.write({ whole = 3 })).whole))
