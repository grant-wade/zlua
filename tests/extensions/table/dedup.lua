local function assert_parts(actual, expected)
  assert(#actual == #expected)
  for index = 1, #expected do
    assert(rawequal(actual[index], expected[index]))
  end
end

assert_parts(table.dedup({}), {})
assert_parts(table.dedup({3, 1, 3, 2, 1}), {3, 1, 2})
assert_parts(table.dedup({true, false, true, "x", "x"}), {true, false, "x"})

local numbers = table.dedup({1, 1.0, 2.0, 2})
assert_parts(numbers, {1, 2.0})
assert(math.type(numbers[1]) == "integer")
assert(math.type(numbers[2]) == "float")

local first = {}
local second = {}
local refs = table.dedup({first, first, second, second})
assert_parts(refs, {first, second})

local equal_mt = {__eq = function() return true end}
local equal_first = setmetatable({}, equal_mt)
local equal_second = setmetatable({}, equal_mt)
assert(equal_first == equal_second)
assert_parts(table.dedup({equal_first, equal_second}), {equal_first, equal_second})

local nan = 0 / 0
local nans = table.dedup({nan, nan})
assert(#nans == 2)
assert(nans[1] ~= nans[1] and nans[2] ~= nans[2])

local input = {"a", "b", "a", label = "kept"}
local input_result = table.dedup(input)
assert_parts(input_result, {"a", "b"})
assert(input_result.label == nil)
assert(#input == 3 and input[3] == "a" and input.label == "kept")

assert(not pcall(table.dedup))
assert(not pcall(table.dedup, "not a table"))
assert(not pcall(table.dedup, setmetatable({}, {__len = function() return 1000001 end})))

print("table.dedup extension ok")
