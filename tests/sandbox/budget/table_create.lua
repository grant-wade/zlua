-- outcome: error
-- message: instruction limit exceeded
while true do local t = table.create(1 << 20) end
