-- expect: pass
-- stage: runtime
-- feature: coroutine
-- normalize: none

local lim = 1000000
for _, j in ipairs{lim - 1, lim, lim + 1, lim + 5} do
  local co = coroutine.create(function() return table.unpack({}, 1, j) end)
  print(j, (coroutine.resume(co)))
end
print(coroutine.resume(coroutine.create(function() return 1, 2, 3 end)))
print(coroutine.wrap(function() return 1, 2, 3 end)())
