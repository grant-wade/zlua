-- expect: pass
-- stage: stdlib
-- feature: stdlib-table
-- normalize: none

-- Table functions convert a __len result like luaL_len: integral floats and
-- numeric strings are accepted, anything else raises.

local function with_len(n, items)
  return setmetatable(items or {}, { __len = function() return n end })
end

local function check(label, fn, ...)
  print(label, pcall(fn, ...))
end

local t = with_len(2.0, { "a", "b" })
table.insert(t, "c")
print("insert", rawget(t, 3))
print("remove", table.remove(with_len(2.0, { "a", "b" })))
print("concat", table.concat(with_len(3.0, { "x", "y", "z" }), ","))
print("unpack", table.unpack(with_len(2.0, { 1, 2, 3 })))
print("string len", table.concat(with_len("2", { "p", "q", "r" }), "-"))
print("string float len", table.concat(with_len("2.0", { "p", "q", "r" }), "-"))

check("fractional", table.concat, with_len(1.5, { "a" }))
check("non numeric", table.concat, with_len("x", { "a" }))
check("boolean", table.insert, with_len(true), 1)
check("nil", table.remove, with_len(nil))
