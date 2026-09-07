-- expect: pass
-- stage: runtime
-- feature: userdata-equality
-- normalize: none
local a, b = io.stdout, io.stderr
local ma, mb = getmetatable(a), getmetatable(b)
local calls = 0
local eq = function(x, y) calls = calls + 1; return true end
debug.setmetatable(a, {__eq=eq})
debug.setmetatable(b, {__eq=eq})
assert(a == b)
local same = a == b; assert(same)
if a ~= b then error('branch equality') end
assert(not rawequal(a, b))
local before = calls
assert(a == a and rawequal(a, a) and calls == before)
-- Mixed table/userdata comparisons are covered by embedding tests: zlua
-- currently represents its Lua-visible file handles with internal tables.
assert(a ~= 1 and a ~= nil and calls == before)
debug.setmetatable(a, {__eq=function() return false end})
assert(a ~= b and b == a)
local marker = {}
debug.setmetatable(a, {__eq=function() error(marker, 0) end})
local ok, err = pcall(function() return a == b end)
assert(not ok and err == marker)
debug.setmetatable(a, {__eq=function() coroutine.yield('eq'); return true end})
local co = coroutine.create(function()
    local result = a == b
    assert(result)
    if a == b then return 'equal' end
end)
assert(select(2, coroutine.resume(co)) == 'eq')
assert(select(2, coroutine.resume(co)) == 'eq')
assert(select(2, coroutine.resume(co)) == 'equal')
debug.setmetatable(a, ma)
debug.setmetatable(b, mb)
print('userdata equality ok')
