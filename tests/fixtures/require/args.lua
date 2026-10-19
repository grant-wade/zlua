loads = (loads or 0) + 1
return { name = ..., data = select(2, ...), argc = select("#", ...) }
