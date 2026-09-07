local root = ".zlua-fs-walk-test"
fs.remove(root, { recursive = true, missing_ok = true })
assert(fs.mkdir(root .. "/keep/deep", { parents = true }))
assert(fs.mkdir(root .. "/skip/deep", { parents = true }))
assert(fs.write(root .. "/keep/deep/a.txt", "a"))
assert(fs.write(root .. "/skip/deep/b.txt", "b"))

local walker = assert(fs.walk(root))
local seen = {}
for entry in walker do
  seen[(entry.path:sub(#root + 2):gsub("\\", "/"))] = true
  if entry.name == "skip" then assert(walker:skip()) end
end
assert(seen["keep"] and seen["keep/deep"] and seen["keep/deep/a.txt"])
assert(seen["skip"] and not seen["skip/deep"])

local shallow = {}
for entry in fs.walk(root, { max_depth = 1 }) do shallow[entry.name] = true end
assert(shallow.keep and shallow.skip and not shallow["a.txt"])

local scan = fs.scandir(root)
local count = 0
for entry in scan do count = count + 1 end
assert(count == 2)
assert(scan:close())

assert(fs.remove(root, { recursive = true }))
print("walk ok")
