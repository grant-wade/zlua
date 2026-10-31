-- outcome: any
-- max-memory: none
-- max-instructions: none
local depth = 190
load(("function f() "):rep(depth) .. ("end "):rep(depth))
load("return " .. ("("):rep(depth) .. "1" .. (")"):rep(depth))
load("return " .. ("{"):rep(depth) .. "1" .. ("}"):rep(depth))
