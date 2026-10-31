assert(getmetatable(res) == false)
assert(getmetatable(other) == false)
assert(not pcall(setmetatable, res, {}))
