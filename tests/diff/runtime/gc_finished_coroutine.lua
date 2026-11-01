local finalized = 0
for _ = 1, 20000 do
  setmetatable({}, {__gc = function() finalized = finalized + 1 end})
  coroutine.wrap(function() end)()
end
collectgarbage()
print(finalized == 20000)
