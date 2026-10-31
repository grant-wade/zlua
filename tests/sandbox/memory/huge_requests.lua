-- max-instructions: none
assert(not pcall(string.rep, "x", 1 << 40))
assert(not pcall(string.rep, "x", 1 << 62))
assert(not pcall(table.create, 1 << 40))
assert(not pcall(table.create, 1 << 31))
assert(not pcall(table.create, 1 << 24, 1 << 24))
assert(not pcall(string.format, "%99999999d", 1))
assert(not pcall(table.unpack, {}, 1, 1 << 40))
