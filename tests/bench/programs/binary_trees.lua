-- name: programs/binary_trees
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- Allocation-heavy tree building and traversal.

local function bottomUp(depth)
  if depth == 0 then return {} end
  depth = depth - 1
  return { bottomUp(depth), bottomUp(depth) }
end
local function itemCheck(tree)
  if tree[1] then return 1 + itemCheck(tree[1]) + itemCheck(tree[2]) end
  return 1
end
local N = 15
local maxdepth = N
local stretch = maxdepth + 1
print(itemCheck(bottomUp(stretch)))
local long = bottomUp(maxdepth)
for d = 4, maxdepth, 2 do
  local iters = 2 ^ (maxdepth - d + 4)
  local check = 0
  for i = 1, iters do check = check + itemCheck(bottomUp(d)) end
  print(d, check)
end
print(itemCheck(long))
