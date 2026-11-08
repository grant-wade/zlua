-- expect: pass
-- stage: runtime
-- feature: arithmetic
-- normalize: none

local max, min = math.maxinteger, math.mininteger
local values = { 0, 1, -1, 7, -7, 3, max, min, 0.0, -0.0, 0.5, -2.5, 1e308, math.huge, -math.huge, 0 / 0 }

local function show(ok, value)
  if not ok then return "error" end
  if value ~= value then return "nan" end
  return math.type(value) .. ":" .. string.format("%.17g", value)
end

local ops = {
  function(a, b) return a + b end,
  function(a, b) return a - b end,
  function(a, b) return a * b end,
  function(a, b) return a / b end,
  function(a, b) return a // b end,
  function(a, b) return a % b end,
}

for _, op in ipairs(ops) do
  local row = {}
  for _, a in ipairs(values) do
    for _, b in ipairs(values) do
      row[#row + 1] = show(pcall(op, a, b))
    end
  end
  print(table.concat(row, " "))
end

local function constants(a)
  return a + 3, a - 3, a * 3, a / 3, a // 3, a % 3,
    a + 0.5, a - 0.5, a * 0.5, a / 0.5, a // 0.5, a % 0.5,
    a % -3, a // -3, a % -0.5, a // -0.5
end

for _, a in ipairs(values) do
  local row = {}
  for _, v in ipairs({ constants(a) }) do row[#row + 1] = show(true, v) end
  print(table.concat(row, " "))
end

local function zero_divisor(a) return a // 0, a % 0 end
for _, a in ipairs({ 1, -1, 0 }) do print((pcall(zero_divisor, a))) end
print(show(true, min // -1), show(true, min % -1))

local x = 0
for i = 1, 100 do x = x + i * 0.25 - i // 3 + i % 7 end
print(show(true, x))
