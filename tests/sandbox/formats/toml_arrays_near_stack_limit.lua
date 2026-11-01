-- max-memory: none
-- max-instructions: none
local document = "a=" .. ("["):rep(63) .. ("]"):rep(63)
assert(pcall(toml.read, document))
local function recurse()
  pcall(toml.read, document)
  return ("x"):gsub("x", recurse)
end
pcall(recurse)
