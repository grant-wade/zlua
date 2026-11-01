local value, err = fs.read(".zlua-definitely-missing-file")
assert(value == nil)
print(err.code, err.system, tostring(err):match("^read"))
assert(err.operation == "read" and err.path == ".zlua-definitely-missing-file")

local exists, exists_err = fs.exists(".zlua-definitely-missing-file")
assert(exists == false and exists_err == nil)

local ok = pcall(fs.read, true)
assert(not ok)
ok = pcall(fs.mkdir, "x", { parents = "yes" })
assert(not ok)

local function portable(path)
  return (path:gsub("\\", "/"))
end
print(portable(fs.path.join("a", "b", "c.txt")))
print(portable(fs.path.normalize("a/./b/../c")))
print(fs.path.basename("a/b/c.txt"), fs.path.dirname("a/b/c.txt"))
print(fs.path.extension("a/b/c.txt"), fs.path.stem("a/b/c.txt"))
print(fs.path.is_absolute("a/b"), portable(fs.path.relative("a/b", "a/c/d")))

for _, paths in ipairs({
  { "a", "b" },
  { "a", "a" },
  { "a/b", "a" },
  { "a", "a/b" },
  { "a", "../b" },
  { "../a", "../b" },
  { "./a/", "b" },
  { "", "a" },
  { "a", "" },
  { "/a/b", "/a/c/d" },
  { "/", "/" },
  { "/a", "/../b" },
}) do
  print(paths[1], paths[2], portable(fs.path.relative(paths[1], paths[2])))
end
print(pcall(fs.path.relative, "/a", "b"))
print(pcall(fs.path.relative, "a", "/b"))
print(pcall(fs.path.relative, "../a", "b"))
