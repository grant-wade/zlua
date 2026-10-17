-- expect: pass
-- stage: runtime
-- feature: calls
-- normalize: none

-- Library functions called by pcall, xpcall, or other library functions keep
-- their arguments while they call metamethods and callbacks.
local function show(...)
  local out = {}
  for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end
  print(table.concat(out, " "))
end

local function proxy(items, n)
  return setmetatable({}, {
    __len = function() return n or #items end,
    __index = function(_, k) return items[k] end,
    __newindex = function(_, k, v) items[k] = v end,
  })
end

local function named(name)
  return setmetatable({}, { __tostring = function() return name end })
end

local box = {}
local inserted = proxy(box, 5)
show(pcall(table.insert, inserted, 1, "x"))
show(box[1], box[6])
show(pcall(table.insert, proxy(box, 0), "y"), box[1])

show(pcall(table.concat, setmetatable({ "a", "b" }, { __len = function() return 2 end }), ","))
show(pcall(table.concat, proxy({ "p", "q", "r" }), "-", 2, 3))
show(xpcall(table.concat, debug.traceback, proxy({ "a", "b" }), "+"))
show(pcall(pcall, table.concat, proxy({ 1, 2, 3 }), "/"))

show(pcall(table.unpack, proxy({ 10, 20, 30 })))
show(pcall(table.unpack, setmetatable({}, { __index = function(_, k) return k * 10 end }), 1, 3))

local removed = { "a", "b", "c" }
show(pcall(table.remove, proxy(removed), 1), removed[1], removed[2], removed[3])

local source, dest = { 1, 2, 3 }, {}
show(pcall(table.move, proxy(source), 1, 3, 2, proxy(dest)), dest[2], dest[3], dest[4])

local sorted = { 3, 1, 2 }
show(pcall(table.sort, proxy(sorted), function(a, b) return a > b end), sorted[1], sorted[2], sorted[3])

show(pcall(string.format, "%s|%s|%d", named("A"), named("B"), 7))
show(pcall(tostring, named("T")))
show(pcall(print, named("p1"), named("p2"), 3))
show(pcall(string.gsub, "abc", "%w", setmetatable({}, { __index = function(_, c) return c:upper() end })))
show(pcall(string.gsub, "abc", "%w", function(c) return c .. c end))

local function spread(...)
  local joined = table.concat(...)
  return joined
end
show(pcall(spread, proxy({ "u", "v", "w" }), ".", 1, 3))

local co = coroutine.wrap(function(...)
  return pcall(pcall, function(...)
    local got = coroutine.yield(select("#", ...))
    return got, ...
  end, ...)
end)
show(co("a", "b"))
show(co("resumed"))

local collected = proxy({ "g", "c" })
show(pcall(table.concat, setmetatable({}, {
  __len = function() collectgarbage() return 2 end,
  __index = function(_, k) collectgarbage() return collected[k] end,
}), string.rep("=", 2)))
