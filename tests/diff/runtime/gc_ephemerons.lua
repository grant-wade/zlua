-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

do
  local eph = setmetatable({}, { __mode = "k" })
  local watch = setmetatable({}, { __mode = "v" })
  local k1 = {}
  local k2 = {}
  local k3 = {}
  local k4 = {}

  eph[k1] = { next = k2 }
  eph[k2] = { next = k3 }
  eph[k3] = { next = k4 }
  eph[k4] = { payload = "end" }

  watch[1] = k1
  watch[2] = k2
  watch[3] = k3
  watch[4] = k4

  local root = k1

  k1, k2, k3, k4 = nil, nil, nil, nil

  collectgarbage("collect")
  collectgarbage("collect")

  assert(root ~= nil)

  for i = 1, 4 do
    assert(watch[i] ~= nil, "reachable ephemeron chain broke at " .. i)
  end

  root = nil

  collectgarbage("collect")
  collectgarbage("collect")

  assert(next(eph) == nil)

  for i = 1, 4 do
    assert(watch[i] == nil, "dead ephemeron chain survived at " .. i)
  end
end

do
  local eph = setmetatable({}, { __mode = "k" })
  local watch = setmetatable({}, { __mode = "v" })
  local k = {}
  local v = {}

  v.back = k
  eph[k] = v

  watch[1] = k
  watch[2] = v

  k = nil
  v = nil

  collectgarbage("collect")
  collectgarbage("collect")

  assert(watch[1] == nil)
  assert(watch[2] == nil)
  assert(next(eph) == nil)
end

do
  local w = setmetatable({}, { __mode = "v" })

  w[1] = ("this-is-a-dynamically-created-weak-string-%d"):format(987654321)

  collectgarbage("collect")
  collectgarbage("collect")
  collectgarbage("collect")

  assert(w[1] == "this-is-a-dynamically-created-weak-string-987654321")
end
