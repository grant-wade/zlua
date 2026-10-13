# Lua Libraries and Extensions

zlua targets Lua 5.5 and adds `fs`, data-format libraries, and a few string/table helpers. Opening a library only installs Lua-visible functions; host capabilities separately control filesystem, environment, clock, process, and I/O access.

## Library Selection

| Selection | Libraries |
| --- | --- |
| `none` | No libraries; the global environment and `_G` still exist. |
| `base` | Base globals. |
| `safe` | Base, table, string, math, utf8, coroutine, json, toml, msgpack, and csv. |
| `full` | Safe plus io, os, debug, package, and fs. |
| Explicit set | Any combination of the libraries above. |

The CLI defaults to `full` with host access. `zlua.State` defaults to `safe` with sandboxed capabilities.

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

The base library installs `_VERSION = "Lua 5.5"` and the usual core functions:

```text
assert  collectgarbage  dofile  error  getmetatable  ipairs  load
loadfile  next  pairs  pcall  print  rawequal  rawget  rawlen  rawset
select  setmetatable  tonumber  tostring  type  warn  xpcall
```

`warn` follows Lua 5.5, including `@on` and `@off`. Warnings start off, as in the CLI without `-W`, and print to stderr as `Lua warning: <message>`.

`xpcall` runs its message handler at the error point, before to-be-closed variables close.

`loadfile` and `dofile` read through the filesystem capability, or from stdin without a file name.

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

`table.create(nseq[, nrec])` is standard in Lua 5.5.

`collectgarbage` supports Lua 5.5's incremental and generational modes, with generational mode as the default. Use `collectgarbage("collect")` for a full collection or `collectgarbage("step", bytes)` to advance it. Explicit collection works even after `collectgarbage("stop")`. Memory counts and collection timing may differ from C Lua. For host-side controls, see [Garbage Collection](embedding.md#garbage-collection).

### zlua Additions to Core Libraries

| Function | Behavior |
| --- | --- |
| `table.dedup(values)` | Returns unique array elements in first-occurrence order using raw key equality; non-array fields are ignored. |
| `string.strip(value[, chars])` | Removes leading/trailing ASCII whitespace or bytes from `chars`. |
| `string.split(value[, separator[, maxsplit]])` | Splits from the left; omitted separator means ASCII whitespace. |
| `string.rsplit(value[, separator[, maxsplit]])` | Same operation starting from the right. |

These helpers follow Python's `str.split`, `str.rsplit`, and `str.strip`. The separator is plain text, a `nil` separator splits on whitespace, `maxsplit` limits the number of splits (negative or `nil` means no limit), and `chars` is a set of bytes.

`table.dedup` compares values as raw table keys, so `__eq` is ignored and `1` and `1.0` are duplicates. `nil` entries are skipped.

## Host-Facing Libraries

Opening `io`, `os`, `package`, or `fs` does not grant ambient access in an embedded state.

| Operations | Capability |
| --- | --- |
| `io.read`, `io.write`, standard streams, `print` | I/O streams. |
| `io.open`, file methods, `loadfile`, `dofile`, filesystem `require` | Filesystem, plus `std.Io` for std-backed modes. |
| `os.time()` and `os.date()` without an explicit time, local time, `os.clock` | Clock. |
| `os.getenv` | Environment. |
| `os.execute`, `io.popen`, `os.exit` | Process, with configured I/O/environment behavior. |
| `os.remove`, `os.rename` | Filesystem. |
| `fs.*` | Filesystem; std-backed modes also need `std.Io`. |

The CLI configures host capabilities; Zig embedders opt in.

`io.tmpfile()` returns an in-memory file. It needs no filesystem capability and leaves nothing behind.

`os.tmpname()` creates an empty file with a unique `lua_XXXXXX` name, like `mkstemp`: in `TMPDIR` with the host filesystem, or at the root of a sandboxed one.

File handles are `FILE*` userdata, as in C Lua.

Writes are buffered in memory and count toward `max_memory`.

Failed writes return `nil, message, errno, count`. Files cannot grow past `max_file_bytes` (256 MiB by default).

The collector flushes and closes unreachable handles, and `State.deinit` closes any still open. Implicit closes ignore flush failures; explicit `close` and `flush` return `nil, message, errno`.

`/dev/null` is emulated in every filesystem mode, and `/dev/full` on Linux.

File errors follow C Lua: `io.open` returns `nil, "path: No such file or directory", 2`.

`os.date` supports the C99 conversions. Local time comes from the clock capability (`TZ` or `/etc/localtime` with the system clock), and `os.clock` reports process CPU time.

`io.popen` runs the whole command at once: read mode when the handle opens, write mode when it closes.

`os.exit` raises `error.LuaExit`, which `pcall` cannot catch. The CLI exits with the requested status and runs `__gc` finalizers unless `os.exit` was called without `close`.

`package.loadlib` always returns `nil, "dynamic libraries not enabled; check your Lua installation", "absent"`.

## Package Loading

When `package` is open, zlua installs `require`. It also installs `loadfile` and `dofile` when base is not open.

| Field | Default |
| --- | --- |
| `package.path` | `./?.lua;./?/init.lua` |
| `package.cpath` | Empty; native C modules are not loaded. |
| `package.searchers` | Preload searcher, then Lua file searcher. |
| `package.loaded` | Opened libraries and already loaded modules. |
| `package.preload` | Host-preloaded modules. |

`require` needs a filesystem capability for Lua files. Memory files provide module loading without host filesystem access.

## Filesystem Extension

`fs` is included in `full`, excluded from `safe`, and always capability-gated. With `package` open, `require("fs")` returns the same table as the `fs` global.

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

Iterator entries include `name`, `path`, `kind`, `inode`, and `depth` while walking. Operational failures return `nil` plus a structured error; argument and iterator failures raise. `fs.path` provides lexical `join`, `normalize`, `basename`, `dirname`, `extension`, `stem`, `is_absolute`, `relative`, and `separator` helpers without touching the filesystem.

## Data Formats

`json`, `toml`, `msgpack`, and `csv` are in `safe` and `full`. If `package` is also open, `require("json")` and the other names return their existing global tables through `package.loaded`.

All readers accept a string (bytes for MessagePack) or a Lua file handle. File input is consumed from the current position to EOF. Errors are prefixed with the library and operation name.

JSON, TOML, and MessagePack writers share table-shape rules:

- Sequential positive integer keys become arrays.
- String-keyed tables become objects/maps.
- Cycles, sparse arrays, mixed array/object tables, unsupported values, non-string object keys, and non-finite numbers are rejected.

Integers outside the 64-bit signed range raise an error rather than becoming floats.

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

`csv.read(input[, options])` returns an array of row tables; empty cells become `csv.null`. With `header=false`, keys are strings starting at `"0"`. `csv.write(rows[, options])` takes its schema and field order from the first row, flattens nested objects into dot-separated columns, allows later rows to omit fields, and rejects new fields or nested arrays.

| CSV option | Values / default |
| --- | --- |
| `delimiter` | `comma`/`,` (default) or `tab`/`tsv`/tab. |
| `header` | Boolean, default true. |
| `record_terminator` | `crlf` (default) or `lf`. |
| `final_record_terminator` | Boolean, default false. |

CSV cells may be nil/null, booleans, finite numbers, or strings.
