-- outcome: error
-- message: instruction limit exceeded
while true do coroutine.wrap(function() end)() end
