-- fault-sweep: true
-- max-memory: none
-- max-instructions: none
assert(res:value() == 0)
assert(not pcall(res.value, other))
pcall(host_call, function() error("x") end)
host_call(function() end)
host_load("return 1")
host_load("return (")
tostring(res)
