-- expect: pass
-- stage: runtime
-- feature: gc
-- normalize: none

-- A full collection run by a library function keeps that function's
-- arguments alive when they come from multiple results.
local function args()
  return ("collect "):rep(3) .. "collect", "%a+", collectgarbage
end
print(string.gsub(args()))
print(pcall(string.gsub, args()))
print(select("#", string.gsub(args())))
