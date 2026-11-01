-- min-stack: 1048576
-- outcome: error
-- message: instruction limit exceeded
return ("a"):rep(32):find(("a-"):rep(12) .. "b")
