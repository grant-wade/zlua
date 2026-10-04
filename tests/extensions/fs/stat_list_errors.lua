-- Error paths for fs.stat and fs.list.

local root = ".zlua-fs-stat-list-test"
fs.remove(root, { recursive = true, missing_ok = true })
assert(fs.mkdir(root .. "/dir/empty", { parents = true }))
assert(fs.write(root .. "/file.txt", "data"))
assert(fs.write(root .. "/dir/b.txt", "b"))
assert(fs.write(root .. "/dir/a.txt", "a"))

local function show_failure(label, value, err)
  print(label, value, err.code, err.operation, err.path == nil and "no path" or "path", getmetatable(err))
end

local function show_error(label, fn, ...)
  local ok, err = pcall(fn, ...)
  print(label, ok, err)
end

-- Nonexistent paths return nil plus a structured not_found error.
local missing = root .. "/missing"
local value, err = fs.stat(missing)
show_failure("stat missing", value, err)
print("stat missing message", tostring(err) == "stat '" .. missing .. "': FileNotFound", err.system)
print("stat missing nofollow", fs.stat(missing, { follow_symlinks = false }) == nil)

value, err = fs.list(missing)
show_failure("list missing", value, err)
print("list missing message", tostring(err) == "list '" .. missing .. "': FileNotFound", err.path == missing)
print("exists missing", fs.exists(missing))

-- File versus directory.
local file_info = assert(fs.stat(root .. "/file.txt"))
print("stat file", file_info.kind, file_info.size)
local dir_info = assert(fs.stat(root .. "/dir"))
print("stat dir", dir_info.kind)

value, err = fs.list(root .. "/file.txt")
show_failure("list file", value, err)

-- A path below a regular file fails without raising; the exact OS error varies.
value, err = fs.stat(root .. "/file.txt/child")
print("stat below file", value, err.operation, type(err.code))
value, err = fs.list(root .. "/file.txt/child")
print("list below file", value, err.operation, type(err.code))

-- Listing directories.
local entries = assert(fs.list(root .. "/dir"))
local names = {}
for index, entry in ipairs(entries) do names[index] = entry.name .. ":" .. entry.kind end
print("list dir", #entries, table.concat(names, " "))
print("list empty", #assert(fs.list(root .. "/dir/empty")))
local unsorted = assert(fs.list(root .. "/dir", { sorted = false }))
print("list unsorted", #unsorted)
print("list sorted nil", #assert(fs.list(root .. "/dir", nil)))

-- Argument errors raise instead of returning nil, err.
show_error("stat no args", fs.stat)
show_error("stat number", fs.stat, 42)
show_error("stat bad options", fs.stat, root, "yes")
show_error("stat bad follow", fs.stat, root, { follow_symlinks = "yes" })
show_error("list no args", fs.list)
show_error("list table", fs.list, {})
show_error("list bad options", fs.list, root, 1)
show_error("list bad sorted", fs.list, root, { sorted = 1 })

assert(fs.remove(root, { recursive = true }))
print("cleanup", fs.exists(root))
