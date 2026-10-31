-- fault-sweep: true
-- max-memory: none
-- max-instructions: none
local big = {} for i = 1, 200 do big[i] = 200 - i end
table.sort(big, function(a, b) return a < b end)
table.concat({1, 2, 3}, ",") table.insert(big, 1) table.insert(big, 1, 0) table.remove(big) table.remove(big, 1) table.move(big, 1, 5, 2)
table.unpack(big, 1, 10) table.pack(1, 2, 3) table.dedup({1, 1, 2}) table.create(8, 8)
local w = setmetatable({}, {__mode = "k"}) for i = 1, 20 do w[{}] = i end
local v = setmetatable({}, {__mode = "v"}) for i = 1, 20 do v[i] = {} end
for k, x in pairs({a = 1, b = 2}) do end for i, x in ipairs({1, 2}) do end
