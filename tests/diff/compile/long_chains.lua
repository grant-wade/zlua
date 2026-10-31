local function show(ok, message) print(ok, (tostring(message):gsub("^[^:]*:%d+: ", ""))) end
local function f() return f end
_G.f = f
print(load("return f" .. ("()"):rep(20000))() == f)
print(load("return 1" .. (" + 1"):rep(20000))())
print(load("local a = ... return a" .. (" + 1"):rep(20000))(2))
print(load("local a = ... return a" .. (" + a"):rep(20000))(2))
print(load("return false" .. (" or false"):rep(20000) .. " or 3")())
print(load("return true" .. (" and true"):rep(20000) .. " and 4")())
print(load("local a = ... if a" .. (" and a"):rep(20000) .. " then return 5 end")(true))
print(load("return f 'x' {} ()" .. (" 'x'"):rep(20000))() == f)
show(pcall(function()
  local function g() return nil end
  return g()
    ()
end))
