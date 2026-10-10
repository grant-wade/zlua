-- name: sustained/stdlib/file_write_chunks
-- category: stdlib
-- expect: pass
-- iterations: 10
-- warmup: 2
-- timeout-ms: 120000
-- Writes 20 MB to one file handle in 10-byte chunks, then reads it back.
-- Sequential writes must stay linear in the total size written.

local name = os.tmpname()
local file = assert(io.open(name, "w"))
local chunk = "0123456789"
for _ = 1, 2000000 do
  file:write(chunk)
end
assert(file:close())

local input = assert(io.open(name, "r"))
local size = input:seek("end")
input:seek("set", 19999990)
local tail = input:read("a")
input:close()
os.remove(name)
print(size, tail)
