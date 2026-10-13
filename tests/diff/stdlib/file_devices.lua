-- expect: pass
-- stage: stdlib
-- feature: io-files
-- normalize: none

-- Device files behave like the host's: `/dev/full` exists only on Linux.
if package.config:sub(1, 1) == "\\" then
  print("no POSIX devices")
  return
end

local null = assert(io.open("/dev/null", "w"))
print(null:write("discarded") == null, null:flush(), null:close())
null = assert(io.open("/dev/null"))
print(null:read("a"), null:read("l"), null:close())

local full, message, code = io.open("/dev/full", "w")
if not full then
  print("no /dev/full", message, code)
  print(pcall(io.output, "/dev/full"))
  return
end
print(full:write("abcd") == full)
print(full:flush())
print(full:flush())
print(full:write("abcd") == full)
print(full:close())

full = assert(io.open("/dev/full", "w"))
print(full:setvbuf("no"))
print(full:write("abcd"))
print(full:write("", "xy", "z"))
print(full:write("") == full)
print(full:setvbuf("line"))
print(full:write("no newline") == full)
print(full:write("line\n") == full)
print(full:close())

io.output("/dev/full")
print(io.write("abcd") == io.output())
print(io.flush())
print(io.flush())
io.write("pending")
print(io.close())
io.output(io.stdout)

local reader = assert(io.open("/dev/full"))
print(reader:read(4) == "\0\0\0\0", reader:read(0) == "")
local zeros, number, after = reader:read(2, "n", 1)
print(zeros == "\0\0", number, after)
print(reader:read(1) == "\0", reader:close())
