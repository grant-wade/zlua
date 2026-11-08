print(select(2, pcall(msgpack.read, "\xdd\xff\xff\xff\xff")))
print(select(2, pcall(msgpack.read, "\x81\x01\x02")))
print(math.type(msgpack.read("\xcf\xff\xff\xff\xff\xff\xff\xff\xff")))
print(select(2, pcall(msgpack.read, "\xd6\xff\x00\x00")))
print(select(2, pcall(msgpack.read, ("\x91"):rep(65) .. "\xc0")))

local floats = msgpack.read(msgpack.write({ 0 / 0, math.huge, -math.huge }))
print(floats[1] ~= floats[1], floats[2], floats[3])

local keyed = msgpack.read(msgpack.write({ ["\xff"] = 1 }))
print(keyed["\xff"])
