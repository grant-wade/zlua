-- expect: pass
-- stage: stdlib
-- feature: system-libraries
-- normalize: none
-- skip-os: windows
-- reason: Windows C Lua cannot open a directory with fopen

local directory = assert(io.open("tests/fixtures"))
print(directory:read(0))
print(pcall(function()
  for line in directory:lines() do print(line) end
end) == false)
directory:close()
