-- expect: pass
-- stage: stdlib
-- feature: io-files
-- normalize: none

-- Error positions name the chunk differently under the harness; drop them.
local function show(ok, ...)
  if ok then return print(ok, ...) end
  print(ok, (tostring(...):gsub("^[^\n]-:%d+: ", "")))
end

-- File handles are FILE* userdata: no fields are visible to raw access.
local f = io.stdout
print(type(f), io.type(f), getmetatable(f).__name)
print(f.read == io.stdout.read, f.write == io.stderr.write, f.nosuch, f[1])
print(pcall(next, f))
show(pcall(function() for _ in pairs(f) do end end))
print(pcall(rawget, f, "read"))
print(pcall(rawset, f, "x", 1))
print(pcall(rawlen, f))
show(pcall(function() return #f end))
show(pcall(function() f.x = 1 end))
show(pcall(function() return f < f end))
show(pcall(function() return f .. "" end))
show(pcall(function() return f() end))
print(pcall(setmetatable, f, {}))
print(rawequal(f, io.stdout), f == io.stdout, f == io.stderr)
print(pcall(ipairs(f), f, 0))
print(debug.getuservalue(f))
print(pcall(debug.setuservalue, f, 1))

-- io.type and tostring.
print(pcall(io.type))
print(io.type(nil), io.type({}), io.type("file"), io.type(io.stdin))
local closed = io.open("/dev/null")
print(tostring(closed):match("^file %(0x%x+%)$") ~= nil)
print(closed:close())
print(io.type(closed), tostring(closed))
print(pcall(closed.read, closed))
print(pcall(closed.close, closed))
print(pcall(io.close, closed))
print(pcall(getmetatable(f).__tostring, {}))

-- __gc and __close ignore closed and standard files.
local mt = getmetatable(f)
print(select("#", mt.__gc(closed)), select("#", mt.__close(closed)), select("#", mt.__gc(io.stdout)))
do
  local scoped <close> = assert(io.tmpfile())
  scoped:write("closing")
end

-- Standard files cannot be closed.
print(io.stdout:close())
print(io.stderr:close())
print(io.stdin:close())
print(io.type(io.stdout))
print(pcall(io.close, nil))

-- Closed default files.
io.input(io.open("/dev/null"))
io.input():close()
print(pcall(io.read))
print(pcall(io.lines))
print(pcall(io.input, closed))
io.input(io.stdin)
io.output(io.open("/dev/null", "w"))
io.output():close()
print(pcall(io.write, "x"))
print(pcall(io.flush))
print(pcall(io.close))
io.output(io.stdout)

-- tmpfile: an anonymous "w+" file.
local t = assert(io.tmpfile())
print(io.type(t), t:write("alpha", 1, "\n", 2.5, "\nend") == t)
print(t:seek("cur"), t:seek("set"), t:read("l"), t:read("n"), t:read("a"))
print(t:seek("set", 2), t:write("PH") == t, t:seek("set"), t:read("a"))
print(t:seek("end", 2), t:write("!") == t, t:seek("set", 15), t:read("a"):gsub("%z", "0"))
print(t:setvbuf("no"), t:flush(), t:seek("set", 0), #t:read("a"))
print(t:close(), io.type(t))
local count = 0
for _ = 1, 20 do
  local u = io.tmpfile()
  u:write(("x"):rep(10))
  count = count + u:seek("end")
end
print(count)

-- os.tmpname: unique names of files that exist and can be removed.
local names, seen, unique, exist = {}, {}, true, true
for i = 1, 50 do
  local name = os.tmpname()
  if seen[name] then unique = false end
  seen[name] = true
  names[i] = name
  local handle = io.open(name, "r")
  if handle then
    if handle:read("a") ~= "" then exist = false end
    handle:close()
  else
    exist = false
  end
end
print(unique, exist, #names)
local removed, gone = true, true
for _, name in ipairs(names) do
  if os.remove(name) ~= true then removed = false end
  if io.open(name) ~= nil then gone = false end
end
print(removed, gone)

-- io.lines from a file name returns the file as its fourth result.
local name = os.tmpname()
local w = assert(io.open(name, "w"))
w:write("one\ntwo\n")
w:close()
local iterator, state, control, file = io.lines(name)
print(type(iterator), state, control, io.type(file))
for line in io.lines(name) do io.write(line, ";") end
print()
print(file:close())
print(select("#", io.lines(name)))
os.remove(name)

-- Arguments are checked by metatable, like luaL_checkudata(L, 1, "FILE*").
local handle = io.tmpfile()
local file_mt = getmetatable(handle)
local methods = file_mt.__index
debug.setmetatable(handle, {})
print(io.type(handle), type(handle), tostring(handle):match("^userdata: ") ~= nil)
print(pcall(io.close, handle))
print(pcall(io.output, handle))
print(pcall(io.input, handle))
print(pcall(methods.write, handle, "x"))
print(pcall(methods.read, handle))
print(pcall(file_mt.__tostring, handle))
print(pcall(file_mt.__gc, handle))
debug.setmetatable(handle, { __name = "Thing" })
print(pcall(io.close, handle), tostring(handle):match("^Thing: ") ~= nil)
print(pcall(methods.seek, handle))
debug.setmetatable(handle, nil)
print(pcall(methods.lines, handle))
debug.setmetatable(handle, file_mt)
print(io.type(handle), handle:write("ok") == handle, handle:seek("set"), handle:read("a"))
print(handle:close())
