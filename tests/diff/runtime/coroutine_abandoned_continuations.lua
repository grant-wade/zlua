-- expect: pass
-- stage: runtime
-- feature: coroutine
-- normalize: none

-- An error caught after a yield abandons the calls that were waiting on the
-- yield; later calls at the same depths must not complete them.
local function norm(value)
  if type(value) ~= "string" then return tostring(value) end
  return (value:gsub("^[^:]*:%d+: ", ""))
end

local function h(...) return "h", ... end
local function g() local a, b = h(1) return a, b end
local function f() local a, b = g() return a, b end

local function run(name, protect, body)
  local co = coroutine.wrap(function()
    local results = table.pack(protect(body))
    for i = 1, results.n do results[i] = norm(results[i]) end
    local x, y = f()
    local z = g()
    local t = {}
    for k, v in ipairs({"a", "b"}) do t[k] = v .. h() end
    return "done", table.concat(results, " ", 1, results.n), x, y, z, t[1], t[2]
  end)
  local out = table.pack(co())
  local resumes = 0
  while out[1] ~= "done" do
    resumes = resumes + 1
    out = table.pack(co())
  end
  print(name, resumes, table.unpack(out, 2, out.n))
end

local function handler(m) return "handled: " .. norm(m) end
local function xp(body) return xpcall(body, handler) end
local function yielding_handler(m) coroutine.yield() return "yielded: " .. norm(m) end
local function xpy(body) return xpcall(body, yielding_handler) end

local index_yield = setmetatable({}, {__index = function() coroutine.yield() error("index") end})
local arith_yield = setmetatable({}, {__add = function() coroutine.yield() error("add") end})
local eq_yield = setmetatable({}, {__eq = function() coroutine.yield() error("eq") end})
local lt_yield = setmetatable({}, {__lt = function() coroutine.yield() error("lt") end})
local concat_yield = setmetatable({}, {__concat = function() coroutine.yield() error("concat") end})
local newindex_yield = setmetatable({}, {__newindex = function() coroutine.yield() error("newindex") end})
local call_yield = setmetatable({}, {__call = function() coroutine.yield() error("call") end})
local pairs_yield = setmetatable({}, {__pairs = function() coroutine.yield() error("pairs") end})
local len_yield = setmetatable({}, {__len = function() coroutine.yield() error("len") end})

local bodies = {
  {"index", function() local a, b, c, d, e, f, g, h, i, j, k, l, m = 1; return index_yield.x end},
  {"arith", function() local a, b, c, d, e, f, g, h = 1; local r = arith_yield + 1 return r end},
  {"eq", function() local a, b, c, d = 1; if eq_yield == setmetatable({}, getmetatable(eq_yield)) then return 1 end return 2 end},
  {"lt", function() local a, b, c, d = 1; local r = lt_yield < lt_yield return r end},
  {"concat", function() local a, b, c, d = 1; local r = "a" .. concat_yield .. "b" return r end},
  {"newindex", function() local a, b, c, d = 1; newindex_yield.x = 1 return 1 end},
  {"len", function() local a, b, c, d = 1; local r = #len_yield return r end},
  {"call", function() local a, b, c, d = 1; local r = call_yield() return r end},
  {"tailcall", function() local a, b, c, d = 1; return call_yield() end},
  {"for", function()
    local a, b, c, d = 1
    for k in function() coroutine.yield() error("iterator") end do return k end
  end},
  {"for native", function()
    local a, b, c, d = 1
    for k in pcall, function() coroutine.yield() error("inner") end do return k end
  end},
  {"pairs", function() local a, b, c, d = 1; for k in pairs(pairs_yield) do return k end end},
  {"tail pairs", function() local a, b, c, d = 1; return pairs(pairs_yield) end},
  {"nested", function()
    local a, b, c, d = 1
    local ok, err = pcall(function() local x = index_yield.x return x end)
    coroutine.yield()
    local r = arith_yield + 1
    return ok, err, r
  end},
  {"deep", function()
    local function rec(n) if n == 0 then return index_yield.x end local r = rec(n - 1) return r end
    return rec(5)
  end},
  {"close", function()
    local a, b, c, d = 1
    local x <close> = setmetatable({}, {__close = function() local y = index_yield.y end})
    return index_yield.x
  end},
  {"close yield", function()
    local a, b, c, d = 1
    local x <close> = setmetatable({}, {__close = function() coroutine.yield() local y = h() end})
    return index_yield.x
  end},
  {"pcall in pcall", function()
    local ok, err = pcall(pcall, function() return index_yield.x end)
    local r = index_yield.y
    return ok, err, r
  end},
}

for _, case in ipairs(bodies) do
  run(case[1], pcall, case[2])
  run(case[1] .. " xpcall", xp, case[2])
  run(case[1] .. " xpcall yield", xpy, case[2])
end

-- Errors that leave the coroutine kill it; closing it afterwards is clean.
for _, case in ipairs(bodies) do
  local co = coroutine.create(case[2])
  local ok, err = coroutine.resume(co)
  while ok and coroutine.status(co) == "suspended" do ok, err = coroutine.resume(co) end
  print(case[1], "escaped", ok, norm(err), coroutine.status(co), (coroutine.close(co)))
end

-- Closing a suspended coroutine abandons its pending calls.
for _, case in ipairs(bodies) do
  local co = coroutine.create(function() return pcall(case[2]) end)
  coroutine.resume(co)
  print(case[1], "closed", coroutine.close(co), coroutine.status(co))
end
