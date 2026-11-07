-- expect: pass
-- stage: runtime
-- feature: debug-hooks
-- normalize: none

local function run(name, f)
  local lines = {}
  debug.sethook(function(_, l) lines[#lines + 1] = l end, "l")
  f()
  debug.sethook()
  print(name, table.concat(lines, " "))
end
local a, k = 1, "key"
run("named", function()
  local t = {
    x = a,
    y = a + 1,
  }
  return t
end)
run("array", function()
  local t = {
    a,
    a + 1,
    3,
  }
  return t
end)
run("keyed", function()
  local t = {
    [k] =
      a,
    [k .. "2"] = 2,
  }
  return t
end)
run("nested", function()
  local t = { a,
    { b = a,
      c = 2 },
  }
  return t
end)
run("empty", function()
  local t =
    {}
  return t
end)
run("call arg", function()
  print(
    {
      a,
    } ~= nil)
end)
run("constant fields", function()
  local t = {
    x = 1,
    y = "s",
  }
  return t
end)
run("many items", function()
  local t = { 1, 2, 3, "four",
    5.5, nil, true,
    a, a * 2 }
  return t
end)
run("multret tail", function()
  local t = {
    a,
    select(1, a, a),
  }
  return t
end)
local ok, message = pcall(function()
  local t = {
    x = a,
    y = a .. {},
  }
  return t
end)
print(ok, (message:gsub("^[^:]*:", "")))
