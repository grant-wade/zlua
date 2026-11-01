-- fault-sweep: true
-- max-memory: none
-- max-instructions: none
load("local a <const> = 1 local function f(...) return select('#', ...) end return f(a, 2, 3)")()
load(function() return nil end)
load("return (")
load("return f" .. ("()"):rep(10))
load("return 1" .. (" + 1"):rep(10))
load("local a = ... return a" .. (" or a"):rep(10))
