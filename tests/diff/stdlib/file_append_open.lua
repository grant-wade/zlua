-- expect: pass
-- stage: stdlib
-- feature: io-files
-- normalize: none

local name = os.tmpname()

local function slurp()
  local f = assert(io.open(name, "rb"))
  local data = f:read("a")
  f:close()
  return (data:gsub("\n", "|"))
end

local function save(data)
  local f = assert(io.open(name, "wb"))
  f:write(data)
  f:close()
end

-- Opening in an append mode keeps the existing bytes.
save("start\n")
for _, mode in ipairs({ "a", "ab", "a+", "a+b" }) do
  local f = assert(io.open(name, mode))
  print(mode, f:seek("end"), slurp())
  f:close()
  print(mode, slurp())
end

-- A missing file is created empty.
os.remove(name)
local f = assert(io.open(name, "ab"))
print(io.type(f), slurp())
f:write("first\n")
f:close()
print(slurp())

-- Writes from several append handles all land at the end of the file.
save("start\n")
local a = assert(io.open(name, "ab"))
local b = assert(io.open(name, "ab"))
b:write("B\n")
b:close()
print(slurp())
a:write("A\n")
a:close()
print(slurp())

a = assert(io.open(name, "ab"))
local w = assert(io.open(name, "r+b"))
w:seek("end")
w:write("W\n")
w:flush()
a:write("A2\n")
a:flush()
print(slurp())
w:close()
a:close()
print(slurp())

-- An a+ handle reads what other handles appended and appends after it.
a = assert(io.open(name, "a+b"))
print(a:read("a"))
b = assert(io.open(name, "ab"))
b:write("tail\n")
b:close()
a:seek("set")
print((a:read("a"):gsub("\n", "|")))
a:write("x\n")
a:seek("set")
print((a:read("a"):gsub("\n", "|")))
a:close()
print(slurp())

-- Unbuffered append handles write through at the end each time.
save("")
a = assert(io.open(name, "ab"))
b = assert(io.open(name, "ab"))
a:setvbuf("no")
b:setvbuf("no")
for i = 1, 3 do
  a:write("a", i, "\n")
  b:write("b", i, "\n")
end
a:close()
b:close()
print(slurp())

os.remove(name)
