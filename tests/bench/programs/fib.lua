-- name: programs/fib
-- category: programs
-- expect: pass
-- iterations: 5
-- warmup: 1
-- timeout-ms: 120000
-- Recursive calls and returns.

local function fib(n) if n < 2 then return n end return fib(n-1) + fib(n-2) end
print(fib(35))
