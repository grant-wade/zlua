-- expect: pass
-- stage: stdlib
-- feature: stdlib-table
-- normalize: none

-- Table functions with extreme __len results and index arguments follow
-- ltablib.c's wrapping arithmetic and unsigned range checks.

local maxint, minint = math.maxinteger, math.mininteger

local function with_len(n, items)
  return setmetatable(items or {}, { __len = function() return n end })
end

local function show(label, ok, ...)
  if not ok then
    print(label, false, (tostring(...):gsub("^[^\n]-:(%d+): ", "chunk:%1: ")))
    return
  end
  local parts = { tostring(ok) }
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    parts[#parts + 1] = math.type(v) and math.type(v) .. ":" .. tostring(v) or type(v) == "table" and "table" or tostring(v)
  end
  print(label, table.concat(parts, " "))
end

local function try(label, fn)
  show(label, pcall(fn))
end

local function short_shift(high, low)
  local gap = high - low
  return high <= low or (gap > 0 and gap <= 100)
end

local function keys(t)
  local list = {}
  for k, v in pairs(t) do list[#list + 1] = tostring(k) .. "=" .. tostring(v) end
  table.sort(list)
  return table.concat(list, ",")
end

-- insert
for _, n in ipairs({ maxint, minint, -1, 0, -5 }) do
  for _, pos in ipairs({ 1, 0, -1, maxint, minint, minint + 1, minint + 2 }) do
    if short_shift(n + 1, pos) then
      local t = with_len(n)
      try("insert len=" .. n .. " pos=" .. pos, function()
        table.insert(t, pos, "x")
        return keys(t)
      end)
    end
  end
  local t = with_len(n)
  try("insert len=" .. n .. " append", function()
    table.insert(t, "y")
    return keys(t)
  end)
end

do
  local t = with_len(-5, { [-10] = "a", [-9] = "b", [-5] = "c" })
  try("insert negative shift", function()
    table.insert(t, -10, "z")
    return keys(t)
  end)
end

-- remove
for _, n in ipairs({ maxint, minint, -1, 0 }) do
  for _, pos in ipairs({ 1, 0, -1, maxint, minint + 1, minint + 2 }) do
    if short_shift(n, pos) then
      local t = with_len(n, { [0] = "zero", "one", [-1] = "neg", [maxint] = "max", [minint + 1] = "min1" })
      try("remove len=" .. n .. " pos=" .. pos, function()
        local removed = table.remove(t, pos)
        return removed, keys(t)
      end)
    end
  end
  local t = with_len(n, { [0] = "zero", "one", [-1] = "neg", [maxint] = "max", [minint] = "min" })
  try("remove len=" .. n .. " default", function()
    local removed = table.remove(t)
    return removed, keys(t)
  end)
end

do
  local t = with_len(2, { "a", "b", "c" })
  try("remove size+1", function()
    local removed = table.remove(t, 3)
    return removed, keys(t)
  end)
  local proxy_store = { "p", "q" }
  local proxy = setmetatable({}, {
    __len = function() return 1 end,
    __index = proxy_store,
    __newindex = function(_, k, v) rawset(proxy_store, k, v) end,
  })
  try("remove size+1 proxy", function()
    local removed = table.remove(proxy, 2)
    return removed, keys(proxy_store)
  end)
end

-- concat
do
  local t = with_len(maxint, { "a", "b", [maxint - 1] = "y", [maxint] = "z", [minint] = "m", [minint + 1] = "n" })
  try("concat explicit", function() return table.concat(t, ",", 1, 2) end)
  try("concat top", function() return table.concat(t, ",", maxint - 1) end)
  try("concat max", function() return table.concat(t, ",", maxint, maxint) end)
  try("concat bottom", function() return table.concat(t, ",", minint, minint + 1) end)
  try("concat empty", function() return table.concat(t, ",", maxint, minint) end)
  try("concat hole", function() return table.concat(t, ",", 2) end)
  try("concat minint len", function() return table.concat(with_len(minint, { "a" }), ",") end)
end

-- unpack
do
  local t = with_len(maxint, { 1, 2, [maxint - 1] = "y", [maxint] = "z", [minint] = "m", [minint + 1] = "n" })
  try("unpack top", function() return table.unpack(t, maxint - 1) end)
  try("unpack max", function() return table.unpack(t, maxint, maxint) end)
  try("unpack bottom", function() return table.unpack(t, minint, minint + 1) end)
  try("unpack empty", function() return table.unpack(t, maxint, minint) end)
  try("unpack all", function() return table.unpack(t, minint, maxint) end)
  try("unpack from", function() return table.unpack(t, 1) end)
  try("unpack minint len", function() return table.unpack(with_len(minint, { 1 })) end)
  try("unpack explicit skips len", function()
    return table.unpack(setmetatable({ 1, 2 }, { __len = function() error("len called") end }), 1, 2)
  end)
end

-- move
do
  local src = { [maxint - 1] = "y", [maxint] = "z", [minint] = "m", [minint + 1] = "n", "a", "b" }
  try("move top", function() return keys(table.move(src, maxint - 1, maxint, 1, {})) end)
  try("move bottom", function() return keys(table.move(src, minint, minint + 1, 1, {})) end)
  try("move to top", function() return keys(table.move(src, 1, 2, maxint - 1, {})) end)
  try("move to bottom", function() return keys(table.move(src, 1, 2, minint, {})) end)
  try("move wrap", function() return table.move(src, 1, 2, maxint, {}) end)
  try("move too many", function() return table.move(src, minint, -1, 1, {}) end)
  try("move too many zero", function() return table.move(src, 0, maxint, 1, {}) end)
  try("move wrap all", function() return table.move(src, 1, maxint, 2, {}) end)
  try("move empty", function() return keys(table.move(src, maxint, minint, 1, {})) end)
  try("move float args", function() return keys(table.move(src, 1.0, 2.0, 3.0, {})) end)
  try("move bad arg order", function() return table.move(nil, "x", 1, 1) end)
end

-- sort
try("sort maxint", function() return table.sort(with_len(maxint, { 3, 1 })) end)
try("sort minint", function()
  local t = with_len(minint, { 3, 1 })
  table.sort(t)
  return keys(t)
end)

-- length conversions
local lens = {
  "3", " 0x3 ", "3.0", "3e0", "-1", "9223372036854775807", "9223372036854775808",
  "1.5", "x", "", 3.0, -0.0, 2^53, -2^63, 2^63, 1.5, 1 / 0, 0 / 0, true, {},
}
for _, n in ipairs(lens) do
  local label = (math.type(n) or type(n)) .. ":" .. (type(n) == "table" and "table" or tostring(n))
  try("len " .. label .. " #", function() return #with_len(n) end)
  try("len " .. label .. " insert", function()
    local t = with_len(n)
    table.insert(t, "v")
    return keys(t)
  end)
  try("len " .. label .. " remove", function()
    local t = with_len(n, { "a", "b", "c", "d" })
    return table.remove(t), keys(t)
  end)
  try("len " .. label .. " concat", function() return table.concat(with_len(n, { "a", "b", "c", "d" }), ",", 1, 2) end)
  try("len " .. label .. " unpack", function() return table.unpack(with_len(n, { 1, 2, 3, 4 }), 3) end)
  try("len " .. label .. " sort", function()
    local t = with_len(n, { 4, 3, 2, 1 })
    table.sort(t)
    return keys(t)
  end)
end
