-- expect: pass
-- stage: stdlib
-- feature: io-files
-- normalize: none

local name = os.tmpname()
local other = name .. ".other"

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("a")
  f:close()
  return data
end

local function show(label, data)
  print(label, #data, (data:gsub("%z", "\\0")))
end

-- w+: sequential writes, seeks inside the run, overwrite in the middle.
local f = assert(io.open(name, "w+"))
print(io.type(f), f:write("hello", " ", "world") == f)
print(f:seek("cur"), f:seek("end"), f:seek("cur", 0))
print(f:seek("set", 6))
f:write("WORLD")
print(f:seek("cur"))
print(f:seek("set"))
print(f:read("a"))
f:write("!", 42, " ", 1.5)
print(f:seek("set", 0), f:read(5), f:read(0), f:read("l"))
print(f:read("a"), f:read(1), f:read(0))
f:close()
show("w+", slurp(name))

-- r+: overwrite keeps the bytes after the written range.
f = assert(io.open(name, "r+"))
print(f:read(3))
f:seek("cur", 0)
f:write("XY")
f:seek("set")
print(f:read("a"))
f:seek("set", 1)
f:write("1", "2", "3")
print(f:seek("cur"))
f:close()
show("r+", slurp(name))

-- Seeking past the end and writing fills the gap with zero bytes.
f = assert(io.open(name, "w"))
f:write("ab")
print(f:seek("set", 5))
f:write("cd")
print(f:seek("end"))
f:close()
show("gap", slurp(name))

-- Append modes always write at the end, wherever the position is.
f = assert(io.open(name, "wb"))
f:write("start\n")
f:close()
f = assert(io.open(name, "a+b"))
print(f:seek("cur"), f:seek("end"))
f:write("one\n")
print(f:seek("set", 0))
print(f:read("l"))
f:seek("end")
f:write("two\n")
print(f:seek("cur"))
f:seek("set", 0)
for line in f:lines() do io.write("[", line, "]") end
print()
f:close()
f = assert(io.open(name, "ab"))
print(f:seek("cur"))
f:write("three")
f:seek("set", 0)
f:write("\n")
f:close()
show("append", slurp(name))

-- Read formats over bytes written by the same handle.
f = assert(io.open(name, "w+"))
f:write("10 0x20 -3.5e1 abc\n", "line two\n", "tail")
f:seek("set")
print(f:read("n", "n", "n", "n"))
print(f:read("L"))
print(f:read("L"), f:read("l"), f:read("l"))
f:seek("set", 3)
print(f:read(4), f:read("n"))
f:close()

-- Flushed bytes are visible to another handle; unflushed ones are not
-- required to be, so only flushed states are printed.
f = assert(io.open(name, "w"))
f:write("first")
assert(f:flush())
local reader = assert(io.open(name, "r"))
print(reader:read("a"))
reader:close()
f:setvbuf("no")
f:write(" second")
reader = assert(io.open(name, "r"))
print(reader:read("a"))
reader:close()
f:setvbuf("line")
f:write(" third\n")
reader = assert(io.open(name, "r"))
print(reader:read("a"))
reader:close()
f:close()

-- A long run of small writes, interleaved with position queries.
f = assert(io.open(name, "w+"))
local total = 0
for i = 1, 1000 do
  local piece = (i % 7 == 0) and "seven" or "x"
  f:write(piece)
  total = total + #piece
  if i % 250 == 0 then print(i, f:seek("cur"), f:seek("end")) end
end
print(total, f:seek("cur"))
f:seek("set", 0)
local data = f:read("a")
print(#data, data:sub(1, 20), data:sub(-12))
f:seek("set", 6)
f:write("SEVEN")
f:seek("set", 0)
print(f:read(14))
f:close()
print(#slurp(name))

-- A handle with unflushed writes keeps them when other files change.
f = assert(io.open(name, "w+"))
f:write("kept bytes")
local g = assert(io.open(other, "w"))
g:write("x")
g:close()
f:seek("set", 0)
print(f:read("a"))
f:close()

-- io.output/io.write and io.lines on the written file.
io.output(name)
io.write("alpha\n", 1, "\n", 2.5, "\n")
io.close()
io.output(io.stdout)
for a, b in io.lines(name, "l", "n") do print(a, b) end
for chunk in io.lines(name, 3) do io.write("<", chunk, ">") end
print()

os.remove(name)
os.remove(other)
