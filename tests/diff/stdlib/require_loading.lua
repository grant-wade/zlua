-- expect: pass
-- stage: stdlib
-- feature: package
-- normalize: none

package.path = "tests/fixtures/require/?.lua;tests/fixtures/require/?/init.lua"
package.cpath = "tests/fixtures/require/?.so"

local m, data = require("args")
print(m.name, m.data, m.argc, data, loads)
local again = require("args")
print(again == m, select("#", require("args")), loads)

print(require("sets_loaded"), package.loaded.sets_loaded)
print(require("overrides_loaded"), package.loaded.overrides_loaded)

loads = 0
print(require("returns_nothing"), package.loaded.returns_nothing, loads)
print(require("returns_nothing"), loads)

loads = 0
print(require("returns_false"), package.loaded.returns_false, loads)
print(require("returns_false"), loads)

local a = require("circular_a")
print(a.name, a.b.name, a.b.a == a, package.loaded.circular_a == a)
print(select(2, require("circular_b")))

print(require("reentrant"), depth, package.loaded.reentrant)

print(require("shebang"))
print(require("pkg"))
print(require("pkg.sub"))

package.preload.pre = function(...)
  print("preload loader", ...)
  return { preloaded = true }
end
local pre, pre_data = require("pre")
print(pre.preloaded, pre_data, require("pre") == pre)

package.loaded.manual = "manual value"
print(require("manual"))

package.loaded.falsy = false
package.preload.falsy = function() return "reloaded" end
print(require("falsy"))

setmetatable(package.loaded, { __index = function(_, key)
  if key == "virtual" then return "from __index" end
end })
print(require("virtual"))
setmetatable(package.loaded, nil)

print(require("string") == string, require("package") == package)
print(#package.searchers, package.loaded["args"] == m)
