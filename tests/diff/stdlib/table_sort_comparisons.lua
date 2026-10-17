-- expect: pass
-- stage: stdlib
-- feature: table-sort-order

local seq = {}
local t = {}
local seed = 7
for i = 1, 300 do seed = (seed * 1103515245 + 12345) % 2147483648; t[i] = seed % 50 end
local n = 0
table.sort(t, function(a, b) n = n + 1; seq[#seq+1] = a .. ":" .. b; return a < b end)
print(n, table.concat(t, ","))
local h = 0
for i, s in ipairs(seq) do for c in s:gmatch(".") do h = (h * 31 + c:byte()) % 1000000007 end end
print(h)
print(pcall(table.sort, {5,3,1,4,2,8,7,6,9,10,11,12}, function(a, b) return true end))
local u = {"b", "a", "d", "c"} table.sort(u) print(table.concat(u))
local w = {3,1,2} table.sort(w, function(a,b) return a > b end) print(table.concat(w, " "))
print(pcall(table.sort, {1, "x", 2}))
