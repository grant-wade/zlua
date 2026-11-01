-- max-memory: none
-- max-instructions: none
-- outcome: any
pcall(string.find, ("x"):rep(400), ("x?"):rep(400))
pcall(string.find, ("x"):rep(400), ("(x"):rep(30))
