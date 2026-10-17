-- expect: pass
-- stage: stdlib
-- feature: io-files
-- normalize: none
-- skip-os: windows
-- reason: Windows C Lua uses tmpnam, which names a file without creating it

-- os.tmpname: unique names of files that exist and can be removed.
local names, seen, unique, exist = {}, {}, true, true
for i = 1, 50 do
  local name = os.tmpname()
  if seen[name] then unique = false end
  seen[name] = true
  names[i] = name
  local handle = io.open(name, "r")
  if handle then
    if handle:read("a") ~= "" then exist = false end
    handle:close()
  else
    exist = false
  end
end
print(unique, exist, #names)
local removed, gone = true, true
for _, name in ipairs(names) do
  if os.remove(name) ~= true then removed = false end
  if io.open(name) ~= nil then gone = false end
end
print(removed, gone)
