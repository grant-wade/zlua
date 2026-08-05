local value, err = fs.read(".zlua-definitely-missing-file")
assert(value == nil)
print(err.code, err.system, tostring(err):match("^read"))
assert(err.operation == "read" and err.path == ".zlua-definitely-missing-file")

local exists, exists_err = fs.exists(".zlua-definitely-missing-file")
assert(exists == false and exists_err == nil)

local ok = pcall(fs.read, 42)
assert(not ok)
ok = pcall(fs.mkdir, "x", { parents = "yes" })
assert(not ok)

print(fs.path.join("a", "b", "c.txt"))
print(fs.path.normalize("a/./b/../c"))
print(fs.path.basename("a/b/c.txt"), fs.path.dirname("a/b/c.txt"))
print(fs.path.extension("a/b/c.txt"), fs.path.stem("a/b/c.txt"))
print(fs.path.is_absolute("a/b"), fs.path.relative("a/b", "a/c/d"))
