-- max-memory: none
-- max-instructions: none
local t = {} for i = 1, 500000 do t = {t} end
pcall(csv.write, {t})
