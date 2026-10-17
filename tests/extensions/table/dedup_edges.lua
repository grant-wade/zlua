-- Edge cases for table.dedup.

local function describe(value)
  local kind = type(value)
  if kind == "string" then return string.format("%q", value) end
  if kind == "number" then return math.type(value) .. ":" .. tostring(value) end
  if kind == "table" or kind == "function" or kind == "thread" or kind == "userdata" then return kind end
  return tostring(value)
end

local function show(label, result)
  local parts = {}
  for index = 1, #result do parts[index] = describe(result[index]) end
  print(label, #result, table.concat(parts, " "))
end

local function show_error(label, fn, ...)
  local ok, err = pcall(fn, ...)
  print(label, ok, err)
end

-- Mixed types keep first occurrences in order.
show("mixed", table.dedup({ 1, "1", true, "true", 1, false, "1", true, false }))
show("int float", table.dedup({ 2, 2.0, 2.5, 2.5, 3.0, 3 }))
show("zero", table.dedup({ 0, -0.0, 0.0 }))
show("big float", table.dedup({ 2^53, math.tointeger(2^53) }))
local maxint = table.dedup({ math.maxinteger, math.maxinteger + 0.0 })
print("maxint", #maxint, math.type(maxint[1]), math.type(maxint[2]), maxint[2] == 2^63)
show("inf", table.dedup({ math.huge, -math.huge, math.huge, 1/0 }))

-- NaN is never equal to itself, so every NaN is kept.
local nan = 0 / 0
local nans = table.dedup({ nan, 1, nan, 1, -nan })
print("nan count", #nans, nans[1] ~= nans[1], nans[2], nans[3] ~= nans[3], nans[4] ~= nans[4])

-- Functions, coroutines, and tables compare by identity.
local f = function() end
local co = coroutine.create(f)
local t = {}
show("refs", table.dedup({ f, co, t, f, co, t, {} }))
print("ref identity", table.dedup({ t, t })[1] == t)

-- Nil holes inside the border are skipped; the result is a proper sequence.
show("holes", table.dedup({ 1, nil, 2, nil, 1, 3 }))
local holes = table.dedup({ nil, nil, "a" })
show("leading holes", holes)
show("all nil", table.dedup({ nil, nil }))
local packed = table.pack("x", nil, "x", nil)
show("packed n ignored", table.dedup(packed))
print("packed n", table.dedup(packed).n)

-- Only 1..#t is read; hash keys and keys beyond the border are ignored.
local sparse = { "a", "b", "a" }
sparse[10] = "z"
sparse.key = "a"
show("sparse", table.dedup(sparse))
show("hash only", table.dedup({ x = 1, y = 2 }))
show("zero index", table.dedup({ [0] = "zero", "one" }))

-- The input is not modified and the result is a new table.
local input = { 3, 3, 4 }
local output = table.dedup(input)
print("input kept", #input, input[1], input[2], input[3], output ~= input)

-- __len and __index are honored when reading the input sequence.
local proxy = setmetatable({}, {
  __len = function() return 4 end,
  __index = function(_, key) return ({ "p", "q", "p", "r" })[key] end,
})
show("proxy", table.dedup(proxy))
local zero_len = setmetatable({ 1, 2, 3 }, { __len = function() return 0 end })
show("zero len", table.dedup(zero_len))
local negative_len = setmetatable({ 1 }, { __len = function() return -3 end })
show("negative len", table.dedup(negative_len))
local float_len = setmetatable({ "a", "a", "b" }, { __len = function() return 3.0 end })
show("float len", table.dedup(float_len))

-- __eq is ignored: deduplication uses raw equality.
local mt = { __eq = function() return true end }
local a, b = setmetatable({}, mt), setmetatable({}, mt)
print("eq ignored", #table.dedup({ a, b, a }))

-- The result has no metatable even if the input does.
print("metatable", getmetatable(table.dedup(setmetatable({ 1 }, {}))))

-- Argument errors.
show_error("no args", table.dedup)
show_error("string", table.dedup, "abc")
show_error("number", table.dedup, 1)
show_error("nil", table.dedup, nil)
show_error("bad len", table.dedup, setmetatable({}, { __len = function() return "x" end }))
show_error("fractional len", table.dedup, setmetatable({}, { __len = function() return 1.5 end }))
show_error("huge len", table.dedup, setmetatable({}, { __len = function() return 1000001 end }))
show_error("index error", table.dedup, setmetatable({}, {
  __len = function() return 1 end,
  __index = function() error("index boom", 0) end,
}))
