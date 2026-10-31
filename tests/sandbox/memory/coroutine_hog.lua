-- outcome: error
-- message: memory limit exceeded
local t = {} while true do t[#t + 1] = coroutine.create(function() end) end
