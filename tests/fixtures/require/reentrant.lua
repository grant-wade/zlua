depth = (depth or 0) + 1
local mine = depth
if depth < 3 then require(...) end
return "depth " .. mine
