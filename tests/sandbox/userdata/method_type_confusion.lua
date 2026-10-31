assert(not pcall(res.value, other))
assert(not pcall(res.value, 1))
assert(not pcall(res.value))
assert(not pcall(other.get, res))
