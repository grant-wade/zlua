-- fault-sweep: true
-- max-memory: none
-- max-instructions: none
json.read(json.write({a = 1, b = {1, 2, 3}, c = "s"}))
msgpack.read(msgpack.write({1, 2, {x = 1}}))
toml.write(toml.read('a = 1\n[b]\nc = "s"\nd = [1, 2]\ne.f = {g = 1}\n[[h]]\ni = 2\n'))
csv.read("a,b\n1,2\n") csv.write({{a = 1}})
pcall(json.read, "[1,") pcall(toml.read, "a = [") pcall(msgpack.read, "\xdd\xff") pcall(csv.read, '"')
