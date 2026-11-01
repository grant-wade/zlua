-- max-instructions: 40000000
local function unmix(x)
  x = x ~ (x >> 31) ~ (x >> 62)
  x = x * 0x319642b2d24d8ec3
  x = x ~ (x >> 27) ~ (x >> 54)
  x = x * 0x96de1b173f119089
  x = x ~ (x >> 30) ~ (x >> 60)
  return x
end
local function key(i) return unmix(i << 32 | (i ~ 0x5bd1e995)) end
local t = {}
for i = 1, 50000 do t[key(i)] = i end
local miss = key(50001)
for _ = 1, 1000000 do local v = t[miss] end
assert(t[key(1)] == 1 and t[key(50000)] == 50000 and t[miss] == nil)
