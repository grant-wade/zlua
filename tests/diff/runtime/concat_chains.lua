-- expect: pass
-- stage: runtime
-- feature: concat
-- normalize: paths

local function err(f, ...)
  local ok, message = pcall(f, ...)
  message = tostring(message):gsub("^.-concat_chains%.lua:", "concat_chains.lua:")
  message = message:gsub("^zlua:", "concat_chains.lua:")
  print(ok, message)
end

-- Numbers and strings.
local a, b, c = "a", "b", "c"
print(a .. b .. c, a .. 1 .. b .. 2.5 .. c)
print(1 .. 2 .. 3, 1.0 .. 2 .. -3, -0.0 .. "|" .. 0.0, 10 // 3 .. "/" .. 10 / 4)
print(math.maxinteger .. ":" .. math.mininteger .. ":" .. 2^53)
print("" .. "" .. "", "" .. 1 .. "", #(a .. "" .. b))
print(1e14 .. "", 0.1 .. "|" .. 123456.789 .. "|" .. -1.5)
print(a .. (b .. c), (a .. b) .. c, a .. (b .. (c .. a)))

-- Long chains.
local parts = {}
for i = 1, 40 do parts[i] = tostring(i) end
local long = parts[1] .. parts[2] .. parts[3] .. parts[4] .. parts[5] .. parts[6] .. parts[7] .. parts[8]
  .. parts[9] .. parts[10] .. parts[11] .. parts[12] .. parts[13] .. parts[14] .. parts[15] .. parts[16]
  .. parts[17] .. parts[18] .. parts[19] .. parts[20] .. parts[21] .. parts[22] .. parts[23] .. parts[24]
  .. parts[25] .. parts[26] .. parts[27] .. parts[28] .. parts[29] .. parts[30] .. parts[31] .. parts[32]
print(long, #long, long == table.concat(parts, "", 1, 32))
local s = ""
for i = 1, 5 do s = s .. i .. "," .. i * 2 .. ";" end
print(s)

-- Operands are evaluated left to right; locals are read when reached.
local log = {}
local function f(tag) log[#log + 1] = tag return tag end
print(f("x") .. f("y") .. f("z"), table.concat(log, ","))
local v = "old"
local function change() v = "new" return "!" end
print(v .. change(), v .. change() .. v)
v = "old"
print(v .. "-" .. change() .. v)

-- __concat metamethods in every position.
local trace = {}
local function name(x)
  if type(x) == "table" then return x.name end
  return tostring(x) .. ":" .. (math.type(x) or type(x))
end
local mt = {}
mt.__concat = function(lhs, rhs)
  trace[#trace + 1] = name(lhs) .. "+" .. name(rhs)
  return setmetatable({name = "(" .. name(lhs) .. name(rhs) .. ")"}, mt)
end
local function obj(n) return setmetatable({name = n}, mt) end
local function run(label, fn)
  trace = {}
  local r = fn()
  print(label, type(r) == "table" and r.name or r, table.concat(trace, " "))
end
local P, Q = obj("P"), obj("Q")
run("left", function() return P .. "x" .. "y" end)
run("middle", function() return "x" .. P .. "y" end)
run("right", function() return "x" .. "y" .. P end)
run("numbers", function() return 1 .. P .. 2 .. 3 end)
run("float", function() return P .. 2.5 end)
run("two", function() return P .. Q end)
run("many", function() return "a" .. P .. "b" .. Q .. "c" .. "d" end)
run("all objects", function() return P .. Q .. P .. Q end)
run("grouped", function() return ("a" .. P) .. ("b" .. Q) end)

local str_mt = {__concat = function(l, r)
  local function piece(x) return type(x) == "table" and "T" or x end
  return piece(l) .. piece(r)
end}
local T = setmetatable({}, str_mt)
print(T .. "a" .. "b", "a" .. T .. "b", "a" .. "b" .. T, 1 .. T .. 2, T .. T .. T)

-- Errors name the offending operand.
local t, n = {}, nil
err(function() return "a" .. nil .. "b" end)
err(function() return "a" .. t .. "b" end)
err(function() return t .. "a" .. "b" end)
err(function() return "a" .. "b" .. t end)
err(function() return "a" .. n .. "b" end)
err(function() return n .. "a" end)
err(function() return "a" .. n end)
err(function() return "a" .. undefined_global .. "b" end)
err(function() return "a" .. t.missing .. "b" end)
err(function() return "a" .. true .. "b" end)
err(function() return "a" .. print .. "b" end)
err(function() return 1 .. {} .. 2 end)
err(function() local u = t return u .. 1 .. 2 end)
err(function() return a .. b .. c .. t end)
err(function() return a .. b .. (c .. t) end)
err(function() return (a .. t) .. c end)
err(function() return a .. f("q") .. nil end)
err(function() return "a" .. "x" .. setmetatable({}, {__concat = function() return {} end}) end)
err(function()
  local u = setmetatable({}, {__concat = function() return {} end})
  return "a" .. u .. "x"
end)
err(function() return "a" ..
  t ..
  "b"
end)
err(function() return t ..
  "a" ..
  "b"
end)
local named = setmetatable({}, {__name = "MyType"})
err(function() return "a" .. named .. "b" end)

-- Upvalues and results of method calls carry no misleading names.
local o = {m = function() end}
err(function() return o:m() .. "x" .. "y" end)
err(function() return "x" .. o:m() end)
err(function() return t .. o end)

-- Yields inside __concat suspend and resume the whole chain.
local ymt = {}
ymt.__concat = function(lhs, rhs)
  local got = coroutine.yield(name(lhs) .. "&" .. name(rhs))
  return got
end
local Y = setmetatable({name = "Y"}, ymt)
local co = coroutine.wrap(function(x)
  local r = "a" .. Y .. "b" .. Y .. 1 .. 2
  local r2 = x .. Y
  return r, r2
end)
print(co("p"))
print(co("[first]"))
print(co("[second]"))
print(co("[third]"))

local co2 = coroutine.create(function()
  local pieces = {}
  for i = 1, 3 do
    pieces[i] = "<" .. setmetatable({}, {__concat = function(l, r)
      return coroutine.yield(i) .. "!"
    end}) .. ">" .. i
  end
  return table.concat(pieces, " ")
end)
local ok, value = coroutine.resume(co2)
while coroutine.status(co2) ~= "dead" do
  print("yielded", ok, value)
  ok, value = coroutine.resume(co2, "v" .. value)
end
print("done", ok, value)

local co3 = coroutine.create(function()
  local missing
  return missing .. setmetatable({}, {__concat = function() return coroutine.yield("y") end}) .. "b"
end)
print(coroutine.resume(co3))
local ok3, msg3 = coroutine.resume(co3, "z")
print(ok3, (tostring(msg3):gsub("^.-concat_chains%.lua:", "concat_chains.lua:"):gsub("^zlua:", "concat_chains.lua:")))

-- Metamethod errors and debug names.
err(function() return "a" .. setmetatable({}, {__concat = function() error("boom") end}) .. "b" end)
err(function() return "a" .. setmetatable({}, {__concat = 1}) .. "b" end)
local info
local probe = setmetatable({}, {__concat = function()
  info = debug.getinfo(1, "n")
  return "p"
end})
print("x" .. probe .. "y", info.name, info.namewhat)

-- Line events for multi-line chains and folded constants.
local function lines_of(fn, ...)
  local first = debug.getinfo(fn, "S").linedefined
  local last = debug.getinfo(fn, "S").lastlinedefined
  local seen = {}
  debug.sethook(function(_, line)
    if line > first and line <= last then seen[#seen + 1] = line - first end
  end, "l")
  fn(...)
  debug.sethook()
  return table.concat(seen, " ")
end
print(lines_of(function(p, q)
  local x = 1 +
    2 *
    3
  local y = -
    4
  local s = p ..
    q ..
    "c" ..
    x
  return x, y, s
end, "a", "b"))
