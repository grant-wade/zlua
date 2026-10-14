-- expect: pass
-- stage: stdlib
-- feature: io-files
-- normalize: none

-- No writes at huge positions: C stdio reports that failure at a later flush.
local name = os.tmpname()
local max, min = math.maxinteger, math.mininteger
local offsets = { max, min, max - 1, min + 1, -1, -2 }

local function check(label, open)
  for _, whence in ipairs({ "set", "cur", "end" }) do
    for _, offset in ipairs(offsets) do
      local f = open()
      f:write("abc")
      f:seek("set", 1)
      print(label, whence, offset, f:seek(whence, offset))
      print("", f:seek("cur"), f:seek("set", 1), f:read(1), f:seek("end"))
      f:close()
    end
  end
end

check("tmpfile", function() return assert(io.tmpfile()) end)
check("w+", function() return assert(io.open(name, "w+")) end)

local f = assert(io.open(name, "r"))
print(f:seek("end", max), f:seek("cur", min), f:seek("set", max))
print(f:seek("cur", 0), f:seek("cur", max), f:seek("cur", 1), f:seek("cur", min))
print(f:seek("set"), f:read("a"))
f:close()

os.remove(name)
