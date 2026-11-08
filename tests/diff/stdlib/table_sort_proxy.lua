-- expect: pass
-- stage: stdlib
-- feature: stdlib-table
-- normalize: none

-- table.sort reads and writes elements through the table in place, in the
-- same order as ltablib.c.

local function proxy(values, log)
  return setmetatable({}, {
    __len = function() return #values end,
    __index = function(_, i)
      if log then log[#log + 1] = "get " .. i end
      return values[i]
    end,
    __newindex = function(_, i, v)
      if log then log[#log + 1] = "set " .. i .. "=" .. tostring(v) end
      values[i] = v
    end,
  })
end

for _, values in ipairs({
  { 2, 1 },
  { 1, 2 },
  { 3, 1, 2 },
  { 5, 3, 8, 1, 9, 2, 7 },
  { 4, 4, 4, 4, 4 },
  { 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 },
}) do
  local log = {}
  table.sort(proxy(values, log))
  print(table.concat(values, " "))
  print(#log, table.concat(log, ","))
end

do
  local values, log = {}, {}
  for i = 1, 120 do values[i] = (i * 37) % 101 end
  table.sort(proxy(values, log), function(a, b) return a > b end)
  print(table.concat(values, " "))
  print(#log)
  local writes = 0
  for _, entry in ipairs(log) do
    if entry:sub(1, 3) == "set" then writes = writes + 1 end
  end
  print(writes)
end

do
  local t = { 5, 2, 4, 1, 3 }
  local seen = {}
  table.sort(t, function(a, b)
    seen[#seen + 1] = table.concat(t, "")
    return a < b
  end)
  print(table.concat(t, " "))
  print(table.concat(seen, ","))
end

do
  local t = {}
  for i = 1, 20 do t[i] = 21 - i end
  print(pcall(table.sort, t, function() return true end))
  print(table.concat(t, " "))
end

do
  local t = { 3, 1, 2, 5, 4 }
  local calls = 0
  print(pcall(table.sort, t, function(a, b)
    calls = calls + 1
    if calls == 3 then error("stop", 0) end
    return a < b
  end))
  print(table.concat(t, " "))
end

do
  local t = { 4, 3, 2, 1 }
  table.sort(t, function(a, b)
    t[5] = "x"
    return a < b
  end)
  print(t[1], t[2], t[3], t[4], t[5])
end
