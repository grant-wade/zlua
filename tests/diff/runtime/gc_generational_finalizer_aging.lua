-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none
-- gc-stress: skip
-- reason: waits for automatic minor collections to finalize young garbage

local function finalizes_without_full_collect(label, prepare)
  local name
  prepare(function()
    setmetatable({}, {__gc = function() name = label end})
  end)
  local n = 0
  repeat local _ = {}; n = n + 1 until name or n > 2e6
  print(label, name == label)
end

finalizes_without_full_collect("steady generational", function(make) make() end)

finalizes_without_full_collect("after mode switch", function(make)
  collectgarbage("incremental")
  make()
  collectgarbage("generational")
end)

finalizes_without_full_collect("after full collect", function(make)
  make()
  collectgarbage()
end)
