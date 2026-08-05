local root = ".zlua-fs-basic-test"
fs.remove(root, { recursive = true, missing_ok = true })

assert(fs.mkdir(root .. "/a/b", { parents = true }))
assert(fs.write(root .. "/a/b/data.txt", "hello", { atomic = true }))
local exclusive, exclusive_err = fs.write(root .. "/a/b/data.txt", "no", { exclusive = true })
assert(exclusive == nil and exclusive_err.code == "already_exists")
assert(fs.write(root .. "/a/b/data.txt", " world", { append = true }))
assert(fs.read(root .. "/a/b/data.txt") == "hello world")
assert(fs.exists(root .. "/a/b/data.txt"))
assert(not fs.exists(root .. "/missing"))

local info = assert(fs.stat(root .. "/a/b/data.txt"))
print(info.kind, info.size)

local entries = assert(fs.list(root .. "/a"))
print(#entries, entries[1].name, entries[1].kind)

assert(fs.copy(root .. "/a", root .. "/copied", { recursive = true }))
local copied_again, copied_err = fs.copy(root .. "/a", root .. "/copied", { recursive = true })
assert(copied_again == nil and copied_err.code == "already_exists")
assert(fs.copy(root .. "/a", root .. "/copied", { recursive = true, overwrite = true }))
assert(fs.read(root .. "/copied/b/data.txt") == "hello world")
assert(fs.rename(root .. "/copied/b/data.txt", root .. "/copied/b/renamed.txt"))
assert(fs.move(root .. "/copied/b/renamed.txt", root .. "/copied/b/moved.txt"))
assert(fs.touch(root .. "/empty.txt"))

local file = assert(fs.open(root .. "/file.txt", "w+"))
assert(file:write("abcdef"))
assert(file:seek("set", 0) == 0)
assert(file:read(3) == "abc")
assert(file:tell() == 3)
assert(file:truncate(4))
assert(file:stat().size == 4)
print(file:path(), file:read("all"))
assert(file:close())

local dir = assert(fs.open_dir(root .. "/copied"))
local count = 0
for entry in dir:walk() do count = count + 1 end
print("dir", count, dir:stat().kind)
assert(dir:close())

assert(fs.remove(root, { recursive = true }))
print("ok")
