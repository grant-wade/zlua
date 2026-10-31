local function show(ok, message) print(ok, (tostring(message):gsub("^[^:]*:%d+: ", ""))) end
show(pcall(function() return (1)[nil] end))
show(pcall(function() return (false)[0/0] end))
show(pcall(function() return (nil)[nil] end))
print(("s")[nil], ({})[nil], ({})[0/0])
print(setmetatable({}, {__index = function(t, k) return "got", k end})[nil])
print(setmetatable({}, {__index = function(t, k) return k ~= k end})[0/0])
print(setmetatable({}, {__index = function(t, k) return math.type(k) end})[1.0])
print(setmetatable({}, {__index = setmetatable({}, {__index = function(t, k) return k == nil end})})[nil])
