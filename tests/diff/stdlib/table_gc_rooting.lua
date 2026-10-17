-- expect: pass
-- stage: stdlib
-- feature: stdlib-table
-- normalize: none

-- Library functions that read values and then run Lua code must keep those
-- values alive even when nothing else references them.

local function proxy(data)
  return setmetatable({}, {
    __len = function() return #data end,
    __index = function(_, i) return {v = data[i], s = "item" .. data[i]} end,
    __newindex = function(_, i, w) data[i] = w.v; assert(w.s == "item" .. w.v) end,
  })
end

do
  local data = {}
  for i = 1, 40 do data[i] = (i * 17) % 41 end
  table.sort(proxy(data), function(a, b)
    collectgarbage()
    local junk = {}
    for i = 1, 20 do junk[i] = {v = -1, s = "junk" .. i} end
    return a.v < b.v
  end)
  print(table.concat(data, " "))
end

do
  local fresh = setmetatable({}, {__index = function(_, i)
    collectgarbage()
    return {v = i, s = "item" .. i}
  end})
  local out = {}
  for _, w in ipairs({table.unpack(fresh, 1, 12)}) do out[#out + 1] = w.s end
  print(table.concat(out, " "))
end
