local M = { name = "a" }
package.loaded[...] = M
M.b = require("circular_b")
