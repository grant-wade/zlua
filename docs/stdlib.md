# Lua Standard Library and Extensions

This page documents the Lua-visible libraries zlua opens, how to select them, and the zlua extensions available alongside the Lua standard library. zlua targets `Lua 5.5`, and `_VERSION` is `Lua 5.5` when the base library is open.

For Zig API details, see the generated [API docs](api/api.md). For sandbox capability controls, see [Embedding zlua From Zig](embedding.md).

## Library Selection

zlua separates library selection from host capabilities. Library selection controls which Lua globals and module tables exist. Host capabilities control whether opened functions can touch filesystem, environment, process, clock, or I/O services.

| Selection | Libraries |
| --- | --- |
| `none` | No standard libraries. |
| `base` | Base globals only. |
| `safe` | Base, table, string, math, utf8, coroutine, json, toml, msgpack, and csv. |
| `full` | Safe libraries plus io, os, debug, package, and the zlua `fs` extension. |
| Granular set | Any explicit combination of `base`, `table`, `string`, `math`, `utf8`, `coroutine`, `io`, `os`, `debug`, `package`, `json`, `toml`, `msgpack`, `csv`, and `fs`. |

The command-line interpreter defaults to `full` and host-oriented capabilities. The Zig embedding API defaults to `safe` and sandboxed capabilities.

CLI selection examples:

```sh
zlua --stdlib=safe script.lua
zlua --stdlib=base,string,json -e 'print(json.write({ ok = true }))'
```

Zig embedding selection examples:

```zig
var safe = try zlua.State.init(allocator, .{});
var full = try zlua.State.init(allocator, .{ .stdlib = .full });
```

## Base Globals

The base library installs the core globals and `_G` table:

| Global | Notes |
| --- | --- |
| `_G` | Global environment table installed when any library selection is non-empty. |
| `_VERSION` | `Lua 5.5`. |
| `assert`, `error`, `pcall`, `xpcall` | Error and protected-call helpers. |
| `collectgarbage` | Lua-facing GC control. `step` currently performs full collection-style work. |
| `getmetatable`, `setmetatable` | Metatable access. |
| `ipairs`, `next`, `pairs` | Iteration helpers. |
| `load` | Compile a chunk from a string or reader function. |
| `print`, `warn` | Output helpers using the state's configured output. |
| `rawequal`, `rawget`, `rawlen`, `rawset` | Raw table/string operations. |
| `select` | Vararg selection. |
| `tonumber`, `tostring`, `type` | Conversion and type inspection. |

## Standard Libraries

| Library | Opened global | Functions and fields |
| --- | --- | --- |
| `table` | `table` | `concat`, `dedup`, `insert`, `move`, `pack`, `remove`, `sort`, `unpack`, `create` |
| `string` | `string` | `byte`, `char`, `dump`, `find`, `format`, `gmatch`, `gsub`, `len`, `lower`, `match`, `pack`, `packsize`, `rep`, `reverse`, `sub`, `unpack`, `upper` |
| `math` | `math` | `abs`, `acos`, `asin`, `atan`, `ceil`, `cos`, `deg`, `exp`, `floor`, `fmod`, `frexp`, `huge`, `ldexp`, `log`, `max`, `maxinteger`, `min`, `mininteger`, `modf`, `pi`, `rad`, `random`, `randomseed`, `sin`, `sqrt`, `tan`, `tointeger`, `type`, `ult` |
| `utf8` | `utf8` | `char`, `charpattern`, `codepoint`, `codes`, `len`, `offset` |
| `coroutine` | `coroutine` | `create`, `resume`, `yield`, `status`, `running`, `isyieldable`, `close`, `wrap` |
| `io` | `io` | `read`, `write`, `open`, `input`, `output`, `close`, `flush`, `lines`, `tmpfile`, `type`, `stdin`, `stdout`, `stderr` |
| `os` | `os` | `time`, `clock`, `date`, `getenv`, `setlocale`, `execute`, `remove`, `rename`, `tmpname`, `difftime` |
| `debug` | `debug` | `traceback`, `getinfo`, `getupvalue`, `setupvalue`, `upvalueid`, `upvaluejoin`, `getlocal`, `setlocal`, `getregistry`, `sethook`, `gethook`, `setmetatable`, `setuservalue`, `getuservalue` |
| `package` | `package` | `loaded`, `preload`, `searchers`, `searchpath`, `path`, `cpath`, `config`; also opens `require`, `loadfile`, and `dofile` globals |
| `fs` | `fs` | Filesystem inspection, traversal, file helpers, mutation utilities, directory objects, and `fs.path` |

`table.create` is a zlua helper for preallocating table array/hash capacity. `table.dedup(tbl)` is a zlua extension that returns a new sequence containing the first occurrence of each element in `1..#tbl`; it preserves order, ignores non-array fields, and leaves the input unchanged. Equality follows raw Lua table-key equality, so numeric integer/float equivalents are duplicates, reference values compare by identity without invoking `__eq`, and NaN values remain distinct. Inputs larger than 1,000,000 elements raise an `array too big` error, and sparse-table behavior is unspecified.

The extension library set contains `json`, `toml`, `msgpack`, `csv`, and `fs`.

## Host-Facing Libraries

Opening `io`, `os`, `package`, or `fs` does not by itself grant host access in embedded states. The matching host capability must also be configured.

| Library functions | Required capability |
| --- | --- |
| `io.open`, `io.lines`, file methods, `loadfile`, `dofile`, and filesystem-backed `require` | `filesystem` plus any required `io` handle |
| `io.read`, `io.write`, standard file handles, output helpers | `io` |
| `os.time`, default-time `os.date`, `os.clock` | `clock` and/or `io`, depending on operation |
| `os.getenv` | `environment` |
| `os.execute` | `process`, with configured I/O and environment behavior |
| `os.remove`, `os.rename`, `os.tmpname` | `filesystem` and/or `io`, depending on operation |
| `fs` inspection, traversal, file, and mutation operations | `filesystem`; std-backed host variants also require configured `std.Io` access |

The CLI configures these capabilities for normal interpreter use. Embedded hosts opt in explicitly.

## Package Loading

When `package` is open, zlua installs `require`, `loadfile`, and `dofile` globals. The package table includes:

| Field | Value |
| --- | --- |
| `package.loaded` | Already loaded module table. Opened standard libraries are inserted here. If an extension and `package` are both open, `package.loaded.<name>` is that extension library table. |
| `package.preload` | Preload searcher table. |
| `package.searchers` | Preload searcher followed by Lua file searcher. |
| `package.path` | Defaults to `./?.lua;./?/init.lua`. |
| `package.cpath` | Empty string; native C module loading is not provided. |
| `package.config` | `"/\n;\n?\n!\n-\n"`. |

`require` can load Lua files only when a filesystem capability is available. In embedded sandboxes, use memory-backed files if scripts should be able to load modules without host filesystem access.

## Filesystem Extension

The `fs` extension is included in `full` and can be selected explicitly with `fs`. It is excluded from `safe`; opening it never grants access by itself, and every operation remains gated by the state's filesystem capability. When `package` is open, `require("fs")` returns the `fs` global.

```lua
local fs = require("fs")

for entry in fs.scandir("src") do
  print(entry.path, entry.kind)
end

local walker <close> = assert(fs.walk(".", { max_depth = 4 }))
for entry in walker do
  if entry.kind == "directory" and entry.name == ".git" then walker:skip() end
end

local file <close> = assert(fs.open("output.bin", "w+"))
assert(file:write("hello"))
assert(file:seek("set", 0) == 0)
assert(file:read("all") == "hello")
```

| Member | Behavior |
| --- | --- |
| `fs.stat(path[, options])` | Returns metadata. `follow_symlinks` defaults to true. Timestamps are `{ seconds, nanoseconds }` tables. |
| `fs.exists(path[, options])` | Returns false only for a missing path; other failures return `nil, error`. |
| `fs.list(path[, options])` | Returns entry snapshots sorted by name unless `sorted=false`. |
| `fs.scandir(path)` | Returns a callable, closable directory iterator. |
| `fs.walk(path[, options])` | Returns a callable, closable recursive iterator. Supports `max_depth`; `walker:skip()` prunes the current directory. |
| `fs.read(path[, options])` | Binary-safe whole-file read. `max_bytes` defaults to 256 MiB. |
| `fs.write(path, bytes[, options])` | Options are `append`, `exclusive`, `atomic`, and `create_parents`. |
| `fs.open(path[, mode])` | Opens a file with standard methods plus `stat`, `tell`, `truncate`, `path`, and `sync`. |
| `fs.open_dir(path)` | Returns a closable directory object with `entries`, `walk`, `open`, `stat`, `mkdir`, and `remove`. |
| `fs.mkdir(path[, options])` | Supports `parents` and `exist_ok`. |
| `fs.remove(path[, options])` | Supports `recursive` and `missing_ok`. |
| `fs.copy(source, destination[, options])` | Copies files or directory trees with `recursive=true`; supports `overwrite`. |
| `fs.rename`, `fs.move` | Rename paths; `move` falls back to copy/remove for cross-device files. |
| `fs.touch(path)` | Creates an empty file or updates an existing file. |

Entries contain `name`, `path`, `kind`, `inode`, and, while walking, `depth`. Operational failures return `nil, error`. Errors have `code`, `system`, `operation`, `path`, optional `destination`, and `message`; `tostring(error)` returns the message. Argument errors raise normally, and traversal failures raise because generic `for` has no terminal-error channel.

`fs.path` provides `join`, `normalize`, `basename`, `dirname`, `extension`, `stem`, `is_absolute`, `relative`, and `separator`. These helpers are lexical and perform no filesystem access.

## JSON Extension

The `json` extension is a zlua library, not part of Lua itself. It is included in `safe` and `full`, and can be selected explicitly with `json` in a granular set.

Use the `json` global whenever the json library is open:

```lua
local value = json.read('{"name":"Ada","nums":[1,2,null]}')
print(value.name, value.nums[3] == json.null)
print(json.write(value))
```

If both `json` and `package` are open, `require("json")` also returns the same table through `package.loaded.json`.

| Member | Behavior |
| --- | --- |
| `json.read(text_or_file)` | Parses a JSON document from a string or Lua file handle and returns the Lua representation. File handles are read from their current position to EOF. Empty or invalid documents raise Lua errors prefixed with `json.read`. |
| `json.write(value[, options])` | Encodes a Lua value and returns a JSON string. Unsupported values raise Lua errors prefixed with `json.write`. |
| `json.null` | Sentinel value used to represent JSON `null` in decoded data and emitted as `null` when encoded. |

JSON decoding maps values as follows:

| JSON | Lua |
| --- | --- |
| `null` | `json.null` |
| booleans | booleans |
| numbers | integers when they fit zlua integer range, otherwise numbers |
| strings | strings |
| arrays | 1-indexed tables |
| objects | string-keyed tables |

JSON encoding maps values as follows:

| Lua | JSON |
| --- | --- |
| `nil` or `json.null` | `null` |
| booleans | booleans |
| finite integers and numbers | numbers |
| strings | strings |
| sequential positive-integer-keyed tables | arrays |
| string-keyed tables | objects |

`json.write` rejects cyclic tables, non-finite numbers, unsupported runtime values, sparse arrays with nil holes, mixed array/object tables, and object tables with non-string keys.

`json.write` accepts an optional options table:

| Option | Type | Meaning |
| --- | --- | --- |
| `pretty` | boolean | Enables pretty-printed output. |
| `indent` | non-negative number | Indentation width used by pretty output. |

Example pretty output:

```lua
print(json.write({ a = 1, b = { 2 } }, { pretty = true, indent = 4 }))
```

## TOML Extension

The `toml` extension is included in `safe` and `full`, and can be selected explicitly with `toml` in a granular set.

Use the `toml` global whenever the toml library is open:

```lua
local value = toml.read([[name = "Ada"
ok = true
nums = [1, 2, 3]
]])
print(value.name, value.ok, value.nums[2])
print(toml.write(value))
```

If both `toml` and `package` are open, `require("toml")` also returns the same table through `package.loaded.toml`.

| Member | Behavior |
| --- | --- |
| `toml.read(text_or_file)` | Parses a TOML document from a string or Lua file handle and returns the Lua representation. File handles are read from their current position to EOF. Empty or invalid documents raise Lua errors prefixed with `toml.read`. |
| `toml.write(value[, options])` | Encodes a Lua table and returns a TOML string. Unsupported values raise Lua errors prefixed with `toml.write`. |

TOML decoding maps values as follows:

| TOML | Lua |
| --- | --- |
| booleans | booleans |
| integers | integers when they fit zlua integer range |
| floats | numbers |
| strings | strings |
| dates and datetimes | strings containing the TOML token text |
| arrays | 1-indexed tables |
| tables and inline tables | string-keyed tables |

TOML encoding maps Lua values through the same table-shape rules as `json.write`: sequential positive-integer-keyed tables become arrays, and string-keyed tables become TOML tables. `toml.write` rejects cyclic tables, non-finite numbers, unsupported runtime values, sparse arrays with nil holes, mixed array/object tables, and object tables with non-string keys.

`toml.write` accepts an optional options table:

| Option | Type | Meaning |
| --- | --- | --- |
| `layout` | string | `"inline_tables"`/`"inline"` writes nested tables inline; `"sections"` writes nested object tables as TOML sections where possible. |

## MessagePack Extension

The `msgpack` extension is included in `safe` and `full`, and can be selected explicitly with `msgpack` in a granular set.

Use the `msgpack` global whenever the msgpack library is open:

```lua
local bytes = msgpack.write({
  name = "Ada",
  nums = {1, 2, msgpack.null},
  ok = true,
})
local value = msgpack.read(bytes)
print(value.name, value.ok, value.nums[3] == msgpack.null)
```

If both `msgpack` and `package` are open, `require("msgpack")` also returns the same table through `package.loaded.msgpack`.

| Member | Behavior |
| --- | --- |
| `msgpack.read(bytes_or_file)` | Parses one MessagePack value from a Lua string or Lua file handle and returns the Lua representation. File handles are read from their current position to EOF. Invalid documents raise Lua errors prefixed with `msgpack.read`. |
| `msgpack.write(value)` | Encodes a Lua value and returns a Lua string containing MessagePack bytes. Unsupported values raise Lua errors prefixed with `msgpack.write`. |
| `msgpack.null` | Sentinel value used to represent MessagePack `nil` in decoded data and emitted as `nil` when encoded. |

MessagePack decoding maps values as follows:

| MessagePack | Lua |
| --- | --- |
| `nil` | `msgpack.null` |
| booleans | booleans |
| integers | integers when they fit zlua integer range |
| floats | numbers |
| `str` | strings |
| `bin` | strings, preserving raw bytes |
| arrays | 1-indexed tables |
| maps | string-keyed tables |

MessagePack encoding maps values as follows:

| Lua | MessagePack |
| --- | --- |
| `nil` or `msgpack.null` | `nil` |
| booleans | booleans |
| finite integers and numbers | integers or floats |
| UTF-8 strings | `str` |
| non-UTF-8 strings | `bin` |
| sequential positive-integer-keyed tables | arrays |
| string-keyed tables | maps |

`msgpack.read` expects exactly one complete root value and rejects trailing bytes after that value. `msgpack.write` rejects cyclic tables, non-finite numbers, unsupported runtime values, sparse arrays with nil holes, mixed array/object tables, and object tables with non-string keys.

## CSV Extension

The `csv` extension is included in `safe` and `full`, and can be selected explicitly with `csv` in a granular set.

Use the `csv` global whenever the csv library is open:

```lua
local rows = csv.read("name,age\r\nAda,37\r\nBob,")
print(rows[1].name, rows[1].age, rows[2].age == csv.null)

local text = csv.write({
  { name = "Ada", age = 37 },
  { name = "Bob" },
}, { record_terminator = "lf" })
print(text)
```

If both `csv` and `package` are open, `require("csv")` also returns the same table through `package.loaded.csv`.

| Member | Behavior |
| --- | --- |
| `csv.read(text_or_file[, options])` | Parses CSV or TSV from a string or Lua file handle and returns a 1-indexed array of row tables. File handles are read from their current position to EOF. Invalid documents raise Lua errors prefixed with `csv.read`. |
| `csv.write(rows[, options])` | Encodes a sequence of row tables and returns a CSV string. Unsupported shapes or values raise Lua errors prefixed with `csv.write`. |
| `csv.null` | Sentinel value used to represent empty cells in decoded data and emitted as an empty cell when encoded. |

CSV decoding maps rows as follows:

| CSV | Lua |
| --- | --- |
| header row | Field names for row tables when `header` is true. |
| data rows | 1-indexed array entries. |
| non-empty cells | strings. |
| empty cells | `csv.null`. |
| no header | Generated string keys starting at `"0"`, then `"1"`, and so on. |

CSV encoding expects the root value to be a sequence of row tables. The first row defines the fixed output schema and field order. Nested object tables are flattened into dot-separated column names, later rows may omit first-row fields, and later rows may not add fields outside the first-row schema.

`csv.write` accepts scalar cell values: `nil`, `csv.null`, booleans, finite integers and numbers, and strings. It rejects cyclic tables, non-finite numbers, unsupported runtime values, sparse arrays with nil holes, mixed array/object tables, object tables with non-string keys, non-row root shapes, nested arrays, and extra fields in later rows.

`csv.read` and `csv.write` accept an optional options table:

| Option | Type | Meaning |
| --- | --- | --- |
| `delimiter` | string | `"comma"`/`","` for CSV or `"tab"`/`"tsv"`/`"\t"` for TSV. Defaults to `"comma"`. |
| `header` | boolean | When true, read or write a header row. Defaults to true. |
| `record_terminator` | string | `"crlf"`/`"\r\n"` or `"lf"`/`"\n"` for written records. Defaults to `"crlf"`. |
| `final_record_terminator` | boolean | Whether `csv.write` emits a trailing record terminator. Defaults to false. |
