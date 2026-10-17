-- expect: pass
-- stage: stdlib
-- feature: stdlib-iterators
-- normalize: none

-- Iterator result counts and multi-capture gmatch.

print(select("#", next({})))
print(select("#", next({ 1 })))
print(select("#", next({ 1 }, 1)))
print(select("#", next({ a = 1 }, "a")))

local iter = ipairs({ "x" })
print(select("#", iter({ "x" }, 0)))
print(select("#", iter({ "x" }, 1)))

local g = string.gmatch("abc", "(a)(b)(c)")
print(g())
print(select("#", g()))

g = string.gmatch("aaa", "a")
print(select("#", g()))

g = string.gmatch("k=v", "(%w)=(%w)")
print(select("#", g()))

for a, b, c, d in string.gmatch("abcd abcd", "(a)(b)(c)(d)") do
  print(a, b, c, d)
end

for pos, word in string.gmatch("one two", "()(%a+)") do
  print(pos, word)
end

for k, v, extra in string.gmatch("a=1, b=2", "(%w+)=(%w+)") do
  print(k, v, extra)
end

local captures = {}
for a, b, c, d, e, f in string.gmatch("123456", "(%d)(%d)(%d)(%d)(%d)(%d)") do
  captures[#captures + 1] = table.concat({ a, b, c, d, e, f }, ",")
end
print(table.concat(captures, ";"))

print(select("#", string.gmatch("", "x")()))
