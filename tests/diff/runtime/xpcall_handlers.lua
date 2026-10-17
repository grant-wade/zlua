-- expect: pass
-- stage: runtime
-- feature: errors
-- normalize: none

-- Message handlers run at the error point, on top of the failing frames and
-- before to-be-closed variables are closed.
local function norm(...)
  local out = {}
  for i = 1, select("#", ...) do
    local text = tostring((select(i, ...)))
    text = text:gsub('%[string "zlua"%]', "F"):gsub("[%w_/\\%.%-]*xpcall_handlers%.lua", "F"):gsub("zlua:", "F:")
    out[i] = text
  end
  print(table.concat(out, "\t"))
end
local function close(f) return setmetatable({}, { __close = f }) end
local H = function(m) return "H(" .. tostring(m) .. ")" end

local function inner() error("boom") end
local function outer() inner() end
norm(xpcall(outer, debug.traceback))
norm(xpcall(function()
  local x <close> = close(function(_, e) norm("close sees:", e) end)
  error("orig")
end, function(m) return "handled: " .. m end))

-- Close errors pass through the handler too.
norm(xpcall(function()
  local a <close> = close(function(_, e) norm("a sees", e) end)
  local b <close> = close(function(_, e) norm("b sees", e); error("bclose", 0) end)
  error("orig", 0)
end, H))
norm(xpcall(function()
  local b <close> = close(function(_, e) norm("b sees", e); error("bclose", 0) end)
  return 1
end, H))

-- The innermost handler wins; pcall installs none.
norm(xpcall(function() return xpcall(function() error("in", 0) end, function(m) return "inner:" .. m end) end, H))
norm(xpcall(function() local _, e = pcall(error, "p", 0); error(e .. "!", 0) end, H))
norm(xpcall(function() error("e", 0) end, function(m) local ok, e2 = pcall(error, "z", 0); return m .. e2 .. tostring(ok) end))
norm(xpcall(function() return load(function() error("rd") end) end, H))
norm(xpcall(string.gsub, H, "abc", "%w", function(c) error("cb" .. c, 0) end))
norm(xpcall(function() local function f() error("lvl", 2) end f() end, H))
norm(xpcall(function() return {} .. "x" end, H))
norm(xpcall(function() local t = nil; return t.x end, H))
norm(xpcall(function() undefinedfn() end, H))

-- Handler results.
norm(xpcall(error, function() end, "x"))
norm(xpcall(error, function() return false end, "x"))
norm(select("#", xpcall(error, function() return 1, 2, 3 end, "x")))
norm(xpcall(function() error({ code = 1 }) end, function(e) return e.code + 1 end))
norm(pcall(xpcall, print))

-- Errors in the handler are handled again until Lua gives up.
local n = 0
norm(xpcall(error, function(m) n = n + 1; error(m) end), n)
local function err(level) if type(level) ~= "number" then return level elseif level == 0 then return "END" else error(level - 1) end end
norm(xpcall(error, err, 170))
norm(xpcall(error, err, 300))
local function overflow_seen(m) return tostring(m):find("C stack") ~= nil end
norm(xpcall(error, function(m) if overflow_seen(m) then return m end local x = {} + {} end))
norm(xpcall(error, function(m) if overflow_seen(m) then return m end error("again") end))
norm(xpcall(error, function(m)
  if overflow_seen(m) then return m end
  local t = setmetatable({}, { __index = function() error("idx") end })
  return t.x
end))
n = 0
norm(coroutine.wrap(function() return xpcall(error, function(m) n = n + 1; error(m) end) end)(), n)
norm(xpcall(error, function(m) local x <close> = close(function() error("hclose", 0) end); return "ret" end, "e"))
norm(xpcall(error, function(m) local x <close> = close(function() norm("handler tbc closed") end); return "ret" end, "e"))
norm(xpcall(function() local t = {}; error(t) end, function(m) collectgarbage(); return type(m) end))

-- Coroutines have their own handlers; yields cross xpcall but not handlers.
norm(xpcall(function() return coroutine.resume(coroutine.create(function() error("co", 0) end)) end, H))
norm(xpcall(function() return coroutine.wrap(function() error("co") end)() end, H))
norm(xpcall(function()
  local c = coroutine.create(function()
    local x <close> = close(function(_, e) norm("co close", e) end)
    error("inside", 0)
  end)
  return coroutine.resume(c)
end, H))
local co = coroutine.wrap(function()
  norm("xp", xpcall(function() local v = coroutine.yield(1); error("after " .. v, 0) end, function(m) return "Y(" .. m .. ")" end))
  return "done"
end)
norm(co())
norm(co("resumed"))
local co2 = coroutine.create(function()
  return xpcall(function()
    local v = coroutine.yield("y")
    local function deep() error("after " .. v) end
    deep()
  end, debug.traceback)
end)
norm(coroutine.resume(co2))
norm(coroutine.resume(co2, "R"))
norm(pcall(coroutine.wrap(function() return xpcall(error, function(m) return coroutine.yield(m) end, "v") end)))
local co3 = coroutine.wrap(function()
  return xpcall(function() return pcall(function() local v = coroutine.yield(1); error("pc" .. v, 0) end) end, H)
end)
norm(co3())
norm(co3("X"))
local suspended = coroutine.create(function()
  local clo <close> = close(function() error(134) end)
  xpcall(coroutine.yield, function() return "XXX" end)
end)
coroutine.resume(suspended)
norm(coroutine.close(suspended))

-- Stack overflows leave room for the handler.
local function overflow() return 1 + overflow() end
local ok, msg = xpcall(overflow, debug.traceback)
norm(ok, (msg:gsub("\n.*", "")), select(2, msg:gsub("\n", "")))
norm(xpcall(overflow, function(m)
  local inner_ok, e = pcall(overflow)
  return tostring(inner_ok) .. " " .. e
end))
