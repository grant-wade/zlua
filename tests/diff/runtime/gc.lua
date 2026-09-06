-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

local keep = { answer = 42 }

local i = 1
while i <= 20 do
  local transient = { i, { value = i + 1 } }
  collectgarbage("collect")
  i = i + 1
end

collectgarbage("collect")
collectgarbage("step")

print(keep.answer)

do
  local dead = setmetatable({ name = "dead" }, {
    __gc = function(self)
      print("gc-final", self.name)
    end,
  })
  dead = nil
end

collectgarbage("collect")
collectgarbage("collect")
print("gc-ok")

collectgarbage("stop")
do
  local log = {}
  local properties = setmetatable({}, { __mode = "k" })
  local mt = {}
  local a = setmetatable({ name = "A" }, mt)
  local b = setmetatable({ name = "B" }, mt)
  a.peer = b
  properties[a], properties[b] = "A", "B"

  mt.__gc = function(self)
    assert(properties[self] == self.name)
    log[#log + 1] = self.name
    if self.name == "A" then
      setmetatable({}, { __gc = function() log[#log + 1] = "C" end })
      error("ignored finalizer error", 0)
    end
  end

  setmetatable(b, mt)
  setmetatable(a, mt)
  setmetatable(b, mt)  -- Already registered: must not change finalization order.
  a, b = nil, nil
  collectgarbage("collect")
  assert(table.concat(log) == "AB")
  assert(next(properties) ~= nil)

  collectgarbage("collect")
  assert(table.concat(log) == "ABC")
  assert(next(properties) == nil)
  collectgarbage("collect")
  assert(table.concat(log) == "ABC")
end
collectgarbage("restart")
print("gc-registration-ok")
