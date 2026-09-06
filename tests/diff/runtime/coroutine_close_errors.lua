-- expect: pass
-- stage: runtime
-- feature: coroutine
-- normalize: none

do
  local BODY = {}
  local B_CLOSE = {}
  local log = {}
  local function guard(name, throws)
    return setmetatable({}, {
      __close = function(_, err)
        log[#log + 1] = {
          name = name,
          err = err,
        }

        if throws ~= nil then
          error(throws)
        end
      end,
    })
  end

  local co = coroutine.create(function()
    local a <close> = guard("A")
    local b <close> = guard("B", B_CLOSE)

    coroutine.yield("PAUSED")

    error(BODY)
  end)

  local ok, value = coroutine.resume(co)

  assert(ok)
  assert(value == "PAUSED")
  assert(#log == 0)

  ok, value = coroutine.resume(co)

  assert(not ok)
  assert(value == BODY)
  assert(#log == 0)
  assert(coroutine.status(co) == "dead")

  local closed, close_error = coroutine.close(co)

  assert(not closed)
  assert(close_error == B_CLOSE)
  assert(#log == 2)
  assert(log[1].name == "B")
  assert(log[1].err == BODY)
  assert(log[2].name == "A")
  assert(log[2].err == B_CLOSE)
end

do
  local E = {}
  local seen
  local wrapped = coroutine.wrap(function()
    local x <close> = setmetatable({}, {
      __close = function(_, err)
        seen = err
      end,
    })

    error(E)
  end)

  local ok, err = pcall(wrapped)

  assert(not ok)
  assert(err == E)
  assert(seen == E)
end
