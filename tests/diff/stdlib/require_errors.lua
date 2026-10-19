-- expect: pass
-- stage: stdlib
-- feature: package
-- normalize: none

package.path = "tests/fixtures/require/?.lua;tests/fixtures/require/?/init.lua"
package.cpath = "tests/fixtures/require/?.so;tests/fixtures/require/lib?.so"

print(pcall(require, "missing"))
print(pcall(require, "missing.dotted.name"))

print(pcall(require, "syntax_error"))
print(package.loaded.syntax_error)

loads = 0
print(pcall(require, "runtime_error"))
print(pcall(require, "runtime_error"))
print(loads, package.loaded.runtime_error)

print(package.searchers[1]("missing"))
print(package.searchers[2]("missing"))
print(package.searchers[3]("missing"))
print(package.searchers[3]("missing.sub"))
print(select("#", package.searchers[4]("missing")))
print(package.searchers[4]("missing.sub"))
print(select(2, package.searchers[2]("args")))
print(pcall(package.searchers[2], "syntax_error"))

print(package.searchpath("missing", "a/?.lua;b/?/init.lua"))
print(package.searchpath("x.y", "?.lua;;?"))
print(package.searchpath("x.y", "?.lua", "", ""))
print(package.searchpath("x_y", "?.lua", "_", "+"))
print(package.searchpath("a;b", "?.lua"))
print(package.searchpath("missing", ""))

package.path = "tests/fixtures/require/?.lua;"
print(pcall(require, "missing"))

package.path = nil
print(pcall(require, "missing"))
package.path = "tests/fixtures/require/?.lua"
package.cpath = 12
print(pcall(require, "missing"))
