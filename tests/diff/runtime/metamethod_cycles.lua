-- expect: pass
-- stage: runtime
-- feature: metatables
-- normalize: none

local a = {}
local b = {}

setmetatable(a, { __index = b })
setmetatable(b, { __index = a })

local ok = pcall(function()
  return a.this_key_does_not_exist
end)

assert(not ok)

local c = {}
local d = {}

setmetatable(c, { __newindex = d })
setmetatable(d, { __newindex = c })

ok = pcall(function()
  c.this_key_does_not_exist = 123
end)

assert(not ok)
