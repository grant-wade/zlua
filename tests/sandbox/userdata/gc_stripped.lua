-- stdlib: full
debug.getmetatable(res).__gc = nil
res, res2 = nil, nil
collectgarbage() collectgarbage()
