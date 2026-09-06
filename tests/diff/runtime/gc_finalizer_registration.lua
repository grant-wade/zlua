-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

do
  local calls = 0
  local mt = {}
  local x = setmetatable({}, mt)

  mt.__gc = function()
    calls = calls + 1
  end

  x = nil
  collectgarbage("collect")
  collectgarbage("collect")

  assert(calls == 0)

  local y = setmetatable({}, mt)
  y = nil

  collectgarbage("collect")

  assert(calls == 1)
end

do
  local result = 0
  local mt = {
    __gc = function()
      result = 1
    end,
  }

  local x = setmetatable({}, mt)

  mt.__gc = function()
    result = 2
  end

  x = nil
  collectgarbage("collect")

  assert(result == 2)

  local y = setmetatable({}, mt)

  mt.__gc = nil

  y = nil
  collectgarbage("collect")

  assert(result == 2)
end

do
  collectgarbage("stop")
  local calls = 0
  local mt

  mt = {
    __gc = function(self)
      calls = calls + 1

      if calls == 1 then
        setmetatable(self, nil)
        setmetatable(self, mt)
      end
    end,
  }

  local x = setmetatable({}, mt)
  x = nil

  collectgarbage("collect")
  assert(calls == 1)

  collectgarbage("collect")
  assert(calls == 2)

  collectgarbage("collect")
  assert(calls == 2)
  collectgarbage("restart")
end

do
  collectgarbage("stop")
  local log = {}
  local mt = {
    __gc = function(self)
      log[#log + 1] = self.name
    end,
  }

  local a = setmetatable({ name = "A" }, mt)
  local b = setmetatable({ name = "B" }, mt)
  local c = setmetatable({ name = "C" }, mt)

  a, b, c = nil, nil, nil

  collectgarbage("collect")

  assert(#log == 3)
  assert(log[1] == "C")
  assert(log[2] == "B")
  assert(log[3] == "A")
  collectgarbage("restart")
end
