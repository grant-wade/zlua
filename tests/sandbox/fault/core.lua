-- fault-sweep: true
-- max-memory: none
-- max-instructions: none
local mt = {__index = function(t, k) return k end, __close = function() end, __add = function(a, b) return 1 end, __tostring = function() return "o" end, __concat = function() return "c" end, __len = function() return 3 end, __eq = function() return true end, __call = function(...) return ... end, __gc = function() end}
local o = setmetatable({}, mt)
local s = 0
for i = 1, 40 do local t = {i, x = i} t.y = {t} s = s + #t + o.x:len() end
pcall(error, {1}) pcall(error, "e")
xpcall(function() error("x") end, function(m) return tostring(m) .. "h" end)
do local a <close> = o end
goto done
::done::
collectgarbage() collectgarbage("step") collectgarbage("incremental") collectgarbage("generational") collectgarbage("count")
