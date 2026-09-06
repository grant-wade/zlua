-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

do
  -- Lua 5.5.0 can crash on this chain in generational mode.
  collectgarbage("incremental")
  local parent = {}
  parent.__newindex = parent
  collectgarbage("collect")

  local child = setmetatable({}, parent)
  child.__newindex = { x = "hello" }
  collectgarbage("step")

  assert(parent.__newindex.x == "hello")
end

do
  collectgarbage("generational")

  local anchor = {
    old = true,
  }

  collectgarbage("collect")
  collectgarbage("collect")

  local weak = setmetatable({}, { __mode = "v" })

  for round = 1, 100 do
    local child = {
      round = round,
      payload = { 0x55aa, round },
    }

    anchor.child = child
    weak[1] = child

    child = nil

    for j = 1, 256 do
      local garbage = {
        round,
        j,
        { round + j },
      }
    end

    collectgarbage("step", 0)

    local live = anchor.child

    assert(type(live) == "table")
    assert(live.round == round)
    assert(live.payload[1] == 0x55aa)
    assert(live.payload[2] == round)
    assert(weak[1] == live)
  end

  anchor.child = nil

  collectgarbage("collect")
  collectgarbage("collect")
  collectgarbage("collect")

  assert(weak[1] == nil)

  collectgarbage("incremental")
end
