# Lua Libraries and Extensions

zlua targets Lua 5.5 and adds a few things on top: the `fs` library, data-format libraries, and some string and table helpers. Keep in mind that opening a library only installs its Lua-visible functions. Whether those functions can actually touch the filesystem, environment, clock, processes, or I/O is controlled separately by host capabilities.

## Library Selection

You choose which libraries a state gets with one of these selections:

| Selection | Libraries |
| --- | --- |
| `none` | No libraries; the global environment and `_G` still exist. |
| `base` | Base globals. |
| `safe` | Base, table, string, math, utf8, coroutine, json, toml, msgpack, and csv. |
| `full` | Safe plus io, os, debug, package, and fs. |
| Explicit set | Any combination of the libraries above. |

The CLI defaults to `full` with host access, while `zlua.State` defaults to `safe` with sandboxed capabilities. Both accept a different selection:

```sh
zlua --stdlib=safe script.lua
zlua --stdlib=base,string,json -e 'print(json.write({ ok = true }))'
```

```zig
var lua = try zlua.State.init(allocator, .{
    .stdlib = .{ .custom = .{
        .math = true,
        .json = true,
    } },
});
```

## Lua Library Surface

The base library sets `_VERSION = "Lua 5.5"` and installs the usual core functions:

```text
assert  collectgarbage  dofile  error  getmetatable  ipairs  load
loadfile  next  pairs  pcall  print  rawequal  rawget  rawlen  rawset
select  setmetatable  tonumber  tostring  type  warn  xpcall
```

A few of these deserve a note. `warn` follows Lua 5.5, including the `@on` and `@off` control messages. Warnings start off, as in the CLI without `-W`, and once enabled they print to stderr as `Lua warning: <message>`. `xpcall` runs its message handler at the point of the error, before any to-be-closed variables close. `loadfile` and `dofile` read through the filesystem capability, or from stdin when no file name is given.

The other standard libraries provide these members:

| Library | Members |
| --- | --- |
| `table` | `concat`, `create`, `dedup`, `insert`, `move`, `pack`, `remove`, `sort`, `unpack` |
| `string` | `byte`, `char`, `dump`, `find`, `format`, `gmatch`, `gsub`, `len`, `lower`, `match`, `pack`, `packsize`, `rep`, `reverse`, `rsplit`, `split`, `strip`, `sub`, `unpack`, `upper` |
| `math` | `abs`, `acos`, `asin`, `atan`, `ceil`, `cos`, `deg`, `exp`, `floor`, `fmod`, `frexp`, `huge`, `ldexp`, `log`, `max`, `maxinteger`, `min`, `mininteger`, `modf`, `pi`, `rad`, `random`, `randomseed`, `sin`, `sqrt`, `tan`, `tointeger`, `type`, `ult` |
| `utf8` | `char`, `charpattern`, `codepoint`, `codes`, `len`, `offset` |
| `coroutine` | `close`, `create`, `isyieldable`, `resume`, `running`, `status`, `wrap`, `yield` |
| `io` | `close`, `flush`, `input`, `lines`, `open`, `output`, `popen`, `read`, `stderr`, `stdin`, `stdout`, `tmpfile`, `type`, `write` |
| `os` | `clock`, `date`, `difftime`, `execute`, `exit`, `getenv`, `remove`, `rename`, `setlocale`, `time`, `tmpname` |
| `debug` | `debug`, `gethook`, `getinfo`, `getlocal`, `getmetatable`, `getregistry`, `getupvalue`, `getuservalue`, `sethook`, `setlocal`, `setmetatable`, `setupvalue`, `setuservalue`, `traceback`, `upvalueid`, `upvaluejoin` |
| `package` | `config`, `cpath`, `loaded`, `loadlib`, `path`, `preload`, `searchers`, `searchpath`; also the `require` global |

Most of these are standard Lua. `table.create(nseq[, nrec])` may look like an extension, but it is part of Lua 5.5. The zlua-specific additions are covered in the next section.

`collectgarbage` supports Lua 5.5's incremental and generational modes, and generational is the default. Use `collectgarbage("collect")` for a full collection or `collectgarbage("step", bytes)` to advance one. Explicit collection still works after `collectgarbage("stop")`. Memory counts and collection timing may differ from C Lua. For controls on the host side, see [Garbage Collection](embedding.md#garbage-collection).

### zlua Additions to Core Libraries

zlua adds four helpers to the `table` and `string` libraries:

| Function | Behavior |
| --- | --- |
| `table.dedup(values)` | Returns unique array elements in first-occurrence order using raw key equality; non-array fields are ignored. |
| `string.strip(value[, chars])` | Removes leading/trailing ASCII whitespace or bytes from `chars`. |
| `string.split(value[, separator[, maxsplit]])` | Splits from the left; omitted separator means ASCII whitespace. |
| `string.rsplit(value[, separator[, maxsplit]])` | Same operation starting from the right. |

The string helpers follow Python's `str.split`, `str.rsplit`, and `str.strip`. The separator is plain text rather than a pattern, and a `nil` separator splits on whitespace. `maxsplit` limits the number of splits, with a negative or `nil` value meaning no limit. For `strip`, `chars` is treated as a set of bytes.

`table.dedup` compares values the way raw table keys are compared, so `__eq` is ignored and `1` and `1.0` count as duplicates. `nil` entries are skipped.

## Host-Facing Libraries

In an embedded state, opening `io`, `os`, `package`, or `fs` doesn't by itself give Lua code any access to the host. Each operation needs the matching capability:

| Operations | Capability |
| --- | --- |
| `io.read`, `io.write`, standard streams, `print` | I/O streams. |
| `io.open`, file methods, `loadfile`, `dofile`, filesystem `require` | Filesystem, plus `std.Io` for std-backed modes. |
| `os.time()` and `os.date()` without an explicit time, local time, `os.clock` | Clock. |
| `os.getenv` | Environment. |
| `os.execute`, `io.popen`, `os.exit` | Process, with configured I/O/environment behavior. |
| `os.remove`, `os.rename` | Filesystem. |
| `fs.*` | Filesystem; std-backed modes also need `std.Io`. |

The CLI sets these capabilities up for you, whereas Zig embedders opt in to each one.

### Files

File handles are `FILE*` userdata, as in C Lua, and their errors follow C Lua too: `io.open` returns `nil, "path: No such file or directory", 2`.

Writes are buffered in memory and count toward `max_memory`. A failed write returns `nil, message, errno, count`, and files can't grow past `max_file_bytes` (256 MiB by default). When you close or flush a file explicitly with `close` or `flush`, failures come back as `nil, message, errno`. Handles you don't close yourself are still cleaned up: the collector flushes and closes unreachable ones, and `State.deinit` closes any that remain open. These implicit closes ignore flush failures.

A few special files and temporaries are handled without the host. `/dev/null` is emulated in every filesystem mode, and `/dev/full` is emulated on Linux. `io.tmpfile()` returns an in-memory file, so it needs no filesystem capability and leaves nothing behind. `os.tmpname()` works like `mkstemp`: it creates an empty file with a unique `lua_XXXXXX` name, in `TMPDIR` when using the host filesystem or at the root of a sandboxed one.

### Time, Processes, and Native Libraries

`os.date` supports the C99 conversions. Local time comes from the clock capability (with the system clock, that means `TZ` or `/etc/localtime`), and `os.clock` reports process CPU time.

`io.popen` runs the whole command in one go: in read mode when the handle opens, and in write mode when it closes.

`os.exit` raises `error.LuaExit`, which `pcall` can't catch. The CLI then exits with the requested status and runs `__gc` finalizers, unless `os.exit` was called without `close`.

zlua doesn't load native libraries, so `package.loadlib` always returns `nil, "dynamic libraries not enabled; check your Lua installation", "absent"`.

## Package Loading

Opening `package` installs `require`. If base isn't open, it also installs `loadfile` and `dofile`. The package fields start with these defaults:

| Field | Default |
| --- | --- |
| `package.path` | `./?.lua;./?/init.lua` |
| `package.cpath` | Empty; native C modules are not loaded. |
| `package.searchers` | Preload, Lua file, C, and all-in-one searchers. A C library found on `package.cpath` fails to load. |
| `package.loaded` | Opened libraries and already loaded modules. |
| `package.preload` | Host-preloaded modules. |

Loading Lua files with `require` needs a filesystem capability. If you want module loading without host filesystem access, memory files give you that.

## Filesystem Extension

`fs` is zlua's filesystem library. It's included in `full`, left out of `safe`, and always gated by the filesystem capability. With `package` open, `require("fs")` returns the same table as the `fs` global.

```lua
local fs = require("fs")

for entry in fs.scandir("src") do
  print(entry.path, entry.kind)
end

local file <close> = assert(fs.open("output.bin", "w+"))
assert(file:write("hello"))
assert(file:seek("set", 0) == 0)
assert(file:read("all") == "hello")
```

| Member | Behavior |
| --- | --- |
| `stat(path[, options])` | Metadata; `follow_symlinks` defaults to true. |
| `exists(path[, options])` | False for a missing path; other failures return `nil, error`. |
| `list(path[, options])` | Snapshot entries, sorted unless `sorted=false`. |
| `scandir(path)` | Callable, closable directory iterator. |
| `walk(path[, options])` | Recursive iterator with `max_depth` and `walker:skip()`. |
| `read(path[, options])` | Binary-safe whole-file read; default limit is 256 MiB. |
| `write(path, bytes[, options])` | Supports `append`, `exclusive`, `atomic`, and `create_parents`. |
| `open(path[, mode])` | File handle with standard methods plus `stat`, `tell`, `truncate`, `path`, and `sync`. |
| `open_dir(path)` | Closable directory with `entries`, `walk`, `open`, `stat`, `mkdir`, and `remove`. |
| `mkdir`, `remove`, `copy` | Directory creation/removal/copy with their recursive and overwrite options. |
| `rename`, `move`, `touch` | Path mutation helpers; `move` handles cross-device copy/remove. |

Iterator entries include `name`, `path`, `kind`, and `inode`, plus `depth` while walking. Errors are reported in two ways: operational failures return `nil` plus a structured error, while argument and iterator failures raise.

For pure path manipulation, `fs.path` provides lexical `join`, `normalize`, `basename`, `dirname`, `extension`, `stem`, `is_absolute`, `relative`, and `separator` helpers. None of them touch the filesystem.

## Data Formats

`json`, `toml`, `msgpack`, and `csv` are available in both `safe` and `full`. If `package` is also open, `require("json")` and the other names return the existing global tables through `package.loaded`.

The four libraries share some conventions. Every reader accepts either a string (bytes for MessagePack) or a Lua file handle, and file input is consumed from the current position to EOF. Errors are prefixed with the library and operation name.

The JSON, TOML, and MessagePack writers also agree on how a Lua table maps to the output:

- Sequential positive integer keys become arrays.
- String-keyed tables become objects/maps.
- Cycles, sparse arrays, mixed array/object tables, unsupported values, non-string object keys, and non-finite numbers are rejected.

Integers outside the 64-bit signed range raise an error rather than quietly becoming floats.

### JSON

```lua
local value = json.read('{"name":"Ada","items":[1,null]}')
assert(value.items[2] == json.null)
print(json.write(value, { pretty = true, indent = 2 }))
```

| Member | Behavior |
| --- | --- |
| `json.read(input)` | Decodes null, booleans, numbers, strings, arrays, and objects. Integer literals become Lua integers. |
| `json.write(value[, options])` | Encodes a value. Options are `pretty` and non-negative `indent`. |
| `json.null` | Sentinel for JSON null. Lua `nil` also encodes as null. |

### TOML

```lua
local value = toml.read('name = "Ada"\nok = true')
print(toml.write(value, { layout = "sections" }))
```

| Member | Behavior |
| --- | --- |
| `toml.read(input)` | Decodes scalars, arrays, and tables. Dates/datetimes remain token strings. |
| `toml.write(table[, options])` | Encodes a table. `layout` accepts `inline_tables`/`inline` or `sections`. |

### MessagePack

```lua
local bytes = msgpack.write({ 1, msgpack.null, "ok" })
assert(msgpack.read(bytes)[2] == msgpack.null)
```

| Member | Behavior |
| --- | --- |
| `msgpack.read(input)` | Decodes exactly one complete value and rejects trailing bytes. `str` and `bin` become Lua strings. |
| `msgpack.write(value)` | Uses `str` for UTF-8 strings and `bin` otherwise. |
| `msgpack.null` | Sentinel for MessagePack nil. Lua `nil` also encodes as nil. |

### CSV

```lua
local rows = csv.read("name,age\r\nAda,37\r\nBob,")
assert(rows[2].age == csv.null)

local text = csv.write(rows, { record_terminator = "lf" })
```

`csv.read(input[, options])` returns an array of row tables, with empty cells set to `csv.null`. With `header=false`, the keys are strings starting at `"0"`.

`csv.write(rows[, options])` takes its schema and field order from the first row and flattens nested objects into dot-separated columns. Later rows may omit fields, but they can't introduce new ones, and nested arrays are rejected. Cells may be nil/null, booleans, finite numbers, or strings.

Both functions accept these options:

| CSV option | Values / default |
| --- | --- |
| `delimiter` | `comma`/`,` (default) or `tab`/`tsv`/tab. |
| `header` | Boolean, default true. |
| `record_terminator` | `crlf` (default) or `lf`. |
| `final_record_terminator` | Boolean, default false. |
