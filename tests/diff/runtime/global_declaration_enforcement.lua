-- expect: pass
-- stage: runtime
-- feature: global-decl
-- normalize: none

local env = {}
local good, good_err = load([[
  global writable
  global<const> *

  writable = 17

  return writable
]], "=globals-good", "t", env)

assert(good, good_err)
assert(good() == 17)
assert(env.writable == 17)

local bad = load([[
  global<const> *

  undeclared = 99
]], "=globals-bad", "t", {})

assert(bad == nil)
