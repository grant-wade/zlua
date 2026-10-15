-- expect: pass
-- stage: runtime
-- feature: calls
-- normalize: none
-- gc-stress: skip
-- reason: formats 70000 arguments, which collects 70000 times under stress

-- Callbacks made while a library function holds more than 65535 arguments
-- must not overwrite them.
local N = 70000
local obj = setmetatable({}, {__tostring = function() return "X" end})
local args = {obj}
for i = 2, N do args[i] = i end
local s = string.format("%s," .. string.rep("%d,", N - 1), table.unpack(args))
print(#s, s:sub(1, 8), s:sub(-14), s:find(",65533,65534,65535,65536,65537,", 1, true))
args[1], args[N] = 1, obj
s = string.format(string.rep("%d,", N - 1) .. "%s", table.unpack(args))
print(#s, s:sub(-14))
