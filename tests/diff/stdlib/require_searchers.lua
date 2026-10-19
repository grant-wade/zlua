-- expect: pass
-- stage: stdlib
-- feature: package
-- normalize: none

package.path = "tests/fixtures/require/?.lua"
package.cpath = "tests/fixtures/require/?.so"

local calls = {}
table.insert(package.searchers, 1, function(name, ...)
  calls[#calls + 1] = name .. "#" .. select("#", ...)
  if name == "virtual" then
    return function(modname, extra)
      return { modname = modname, extra = extra }
    end, { tag = "loader data" }
  elseif name == "no_data" then
    return function(...) return select("#", ...) end
  elseif name == "silent" then
    return nil
  elseif name == "number" then
    return 42
  end
  return "\n\tno virtual module '" .. name .. "'"
end)

local v, data = require("virtual")
print(v.modname, v.extra == data, data.tag)
print(require("no_data"))
print(select("#", require("no_data")))
print(require("args").name)
print(table.concat(calls, " "))

print(pcall(require, "silent"))
print(pcall(require, "number"))
print(pcall(require, "missing"))

table.remove(package.searchers, 1)

package.preload.weird = 42
print(pcall(require, "weird"))

package.preload.weird = "a string"
print(pcall(require, "weird"))

package.searchers[#package.searchers + 1] = function(name)
  return function() return "last resort " .. name end, "fallback"
end
print(require("anything"))
print(require("weird"))

local saved = package.searchers
package.searchers = { function() return "only message" end, function() end }
print(pcall(require, "lonely"))
package.searchers = {}
print(pcall(require, "empty"))
package.searchers = nil
print(pcall(require, "none"))
package.searchers = saved

package.searchers[1] = function(name) error("searcher failed for " .. name, 0) end
print(pcall(require, "boom"))
package.searchers[1] = 7
print(pcall(require, "noncallable"))
