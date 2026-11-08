local value = toml.read([==[
point = {
  x = 1, # inline tables may span lines
  y = 2,
}
escape = "\x41\u00e9\U0001F600"
alarm = 07:30
when = 1979-05-27 07:32Z
big = 0xff
octal = 0o17
binary = 0b101
million = 1_000_000
float = 6.626e-34
special = [inf, -inf]
literal = 'C:\path'
multi = """
one \
  two"""

[[fruit]]
name = "apple"
[fruit.color]
skin = "red"

[[fruit]]
name = "banana"
]==])
print(value.point.x, value.point.y, value.escape, value.alarm, value.when)
print(value.big, value.octal, value.binary, value.million, value.float)
print(value.special[1], value.special[2], value.literal, value.multi)
print(value.fruit[1].name, value.fruit[1].color.skin, value.fruit[2].name)

local back = toml.read(toml.write({ a = 0 / 0, b = math.huge, c = -math.huge }))
print(back.a ~= back.a, back.b, back.c)

for _, document in ipairs({
  "a = 1\na = 2",
  "[a]\n[a]",
  "a.b = 1\n[a]",
  "a = { b = 1 }\na.c = 2",
  "[[a]]\n[a]",
  "[a.b]\n[a]\nb.c = 1",
  "a = 01",
  "a = 1979-02-30",
  "a = 'x\ny'",
}) do
  print(select(2, pcall(toml.read, document)))
end
print(select(2, pcall(toml.write, { a = { b = json.null } })))
