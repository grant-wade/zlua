-- expect: pass
-- stage: stdlib
-- feature: io-files
-- normalize: none

local name = os.tmpname()

local function save(data)
  local f = assert(io.open(name, "wb"))
  f:write(data)
  f:close()
end

local function show(...)
  local values = table.pack(...)
  local parts = {}
  for i = 1, values.n do parts[i] = tostring(values[i]) end
  print(values.n, table.concat(parts, " | "))
end

-- A failed format ends the iteration and leaves the later formats unread.
save("abc\n12\n")
local f = assert(io.open(name))
for a, b in f:lines("n", "l") do print("unreached", a, b) end
print(f:read())
f:close()

-- A failure after the first format returns the values read so far and a
-- nil, then later calls continue from where the failed format stopped.
save("x\ny\n3\nz\n")
f = assert(io.open(name))
for a, b, c in f:lines("l", "n", "l") do show(a, b, c) end
print(f:read("a"))
f:close()

-- file:read stops at the same format.
f = assert(io.open(name))
show(f:read("l", "n", "l"))
show(f:read("l", "n", "l"))
f:close()

-- io.lines with formats, including a count that runs out first.
save("10 20\n30\nend")
for a, b, c in io.lines(name, "n", "n", "l") do show(a, b, c) end
for a, b, c in io.lines(name, 4, "n", "L") do show(a, b, c) end
for a, b in io.lines(name, "L", 0) do show(a, b) end

os.remove(name)
