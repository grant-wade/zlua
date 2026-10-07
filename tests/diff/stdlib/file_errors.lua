-- expect: pass
-- stage: stdlib
-- feature: system-libraries
-- normalize: none

local missing = "tests/fixtures/missing_file.txt"
local missing_dir = "tests/fixtures/missing_dir/file.txt"

print(io.open(missing))
print(select("#", io.open(missing)))
print(io.open(missing, "r+"))
print(io.open(missing_dir, "w"))
print(io.open(missing_dir, "a"))
print(io.open(missing_dir, "w+"))

print(pcall(io.lines, missing))
print(pcall(io.input, missing))
print(io.input() == io.stdin)
print(pcall(io.output, missing_dir))
print(io.output() == io.stdout)

print(loadfile(missing))
print(loadfile(missing, "t", {}))
print(pcall(dofile, missing))

print(os.remove(missing))
print(os.rename(missing, "tests/fixtures/renamed_file.txt"))

local file = assert(io.open("tests/fixtures/system_input.txt"))
print(file:read("l"))
print(file:close())
print(pcall(file.read, file))
