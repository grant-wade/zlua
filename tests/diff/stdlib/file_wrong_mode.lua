-- expect: pass
-- stage: stdlib
-- feature: system-libraries
-- normalize: none

local path = os.tmpname()

local out = assert(io.open(path, "w"))
print(out:read("l"))
print(out:read("n", "a"))
print(select("#", out:read("a")))
local function message_of(ok, message)
  return ok, (message:gsub("^.-:%d+: ", ""))
end
print(message_of(pcall(function()
  for line in out:lines() do print(line) end
end)))
io.input(out)
print(io.read("l"))
io.input(io.stdin)
assert(out:write("data\n"))
out:close()

local input = assert(io.open(path, "r"))
print(input:write("x"))
print(input:write("x", "y"))
print(select("#", input:write("x")))
io.output(input)
print(io.write("x"))
io.output(io.stdout)
print(input:read("l"))
input:close()

os.remove(path)

local directory = io.open("tests/fixtures")
if directory and not directory:read(0) then
  print(message_of(pcall(function()
    for line in directory:lines() do print(line) end
  end)))
  directory:close()
end
