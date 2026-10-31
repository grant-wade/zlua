-- outcome: error
-- message: instruction limit exceeded
xpcall(function() while true do end end, function() while true do end end)
while true do end
