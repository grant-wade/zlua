-- expect: pass
-- stage: runtime
-- feature: to-be-closed
-- normalize: none

do
  local log = {}
  local function guard(name)
    return setmetatable({}, {
      __close = function()
        log[#log + 1] = name
      end,
    })
  end

  do
    local a <close> = guard("A")

    do
      local b <close> = guard("B")
      goto outside
    end
  end

  ::outside::

  assert(#log == 2)
  assert(log[1] == "B")
  assert(log[2] == "A")
end

do
  local closed = false
  local resource = setmetatable({}, {
    __close = function()
      assert(not closed)
      closed = true
    end,
  })

  local function outer()
    local x <close> = resource
    local function inner()
      assert(not closed)
      return "A", nil, "C"
    end

    return inner()
  end

  local result = table.pack(outer())

  assert(closed)
  assert(result.n == 3)
  assert(result[1] == "A")
  assert(result[2] == nil)
  assert(result[3] == "C")
end
