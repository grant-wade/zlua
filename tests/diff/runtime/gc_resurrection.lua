-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

local weak_keys = setmetatable({}, { __mode = "k" })
local weak_values = setmetatable({}, { __mode = "v" })
local resurrected
local calls = 0
local mt = {
  __gc = function(self)
    calls = calls + 1

    assert(weak_keys[self] == "secret-property")
    assert(weak_values.object == nil)

    resurrected = self
  end,
}

local object = setmetatable({}, mt)

weak_keys[object] = "secret-property"
weak_values.object = object

object = nil

collectgarbage("collect")

assert(calls == 1)
assert(resurrected ~= nil)
assert(weak_keys[resurrected] == "secret-property")
assert(weak_values.object == nil)

resurrected = nil

collectgarbage("collect")
collectgarbage("collect")

assert(next(weak_keys) == nil)
