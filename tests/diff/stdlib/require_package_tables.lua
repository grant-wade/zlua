-- expect: pass
-- stage: stdlib
-- feature: package
-- normalize: none

package.path = "tests/fixtures/require/?.lua"
package.cpath = "tests/fixtures/require/?.so"
local original = package
local loaded, preload = package.loaded, package.preload

package.loaded = {}
package.preload = {}
preload.from_original = function(name) return "original preload " .. name end
package.preload.from_replacement = function() return "replacement preload" end
print(require("from_original"))
print(loaded.from_original, package.loaded.from_original)
print(require("string") == string)
print(pcall(require, "from_replacement"))
print(pcall(string.rep))
package.loaded, package.preload = loaded, preload

package = nil
print(require("args").name)
original.path = "tests/fixtures/require/pkg/?.lua"
print(require("sub"))
print(pcall(require, "missing"))

package = { searchers = {}, path = "", loaded = {}, preload = {} }
print(require("string") == string, require("sub"))
print(pcall(require, "still_missing"))
original.searchers = nil
print(pcall(require, "no_searchers"))
package = original
