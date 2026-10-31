-- outcome: error
-- message: instruction limit exceeded
return load(("x=1 "):rep(12 << 20))
