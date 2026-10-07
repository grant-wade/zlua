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

`_G` exists even when base is not open. `loadfile` and `dofile` read through the filesystem capability, so in a sandboxed state they fail like a missing file (`cannot open name.lua: filesystem access disabled`). Without a file name they read the stdin capability.

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

`table.create(nseq[, nrec])` is the standard Lua 5.5 constructor: it returns an empty table preallocated for `nseq` array elements and `nrec` other fields. Both sizes must be integers from 0 to 2^31-1.

`collectgarbage` supports Lua 5.5's incremental and generational modes, with generational mode as the default. Use `collectgarbage("collect")` for a full collection or `collectgarbage("step", bytes)` to advance it. Explicit collection works even after `collectgarbage("stop")`. Memory counts and collection timing may differ from C Lua. For host-side controls, see [Garbage Collection](embedding.md#garbage-collection).

### zlua Additions to Core Libraries

| Function | Behavior |
| --- | --- |
| `table.dedup(values)` | Returns unique array elements in first-occurrence order using raw key equality; non-array fields are ignored. |
| `string.strip(value[, chars])` | Removes leading/trailing ASCII whitespace or bytes from `chars`. |
| `string.split(value[, separator[, maxsplit]])` | Splits from the left; omitted separator means ASCII whitespace. |
| `string.rsplit(value[, separator[, maxsplit]])` | Same operation starting from the right. |

These helpers follow Python's `str.split`/`str.rsplit`/`str.strip` conventions:

- `separator` is plain text, not a Lua pattern, and may be several bytes long; matches do not overlap. An empty separator raises an argument error.
- With a separator, leading, trailing, and adjacent separators produce empty strings (`split(",a,", ",")` is `{"", "a", ""}`), and an empty input returns `{""}`.
- With no separator (or `nil`), runs of ASCII space, `\t`, `\n`, `\r`, `\v`, and `\f` separate fields, leading and trailing whitespace is ignored, and empty or all-whitespace input returns `{}`.
- `maxsplit` limits the number of splits, and the unsplit remainder is kept as the last (`split`) or first (`rsplit`) piece. `0` returns the input as one piece; in whitespace mode the remainder loses only the whitespace on the side splitting starts from (`split("  a b  ", nil, 1)` is `{"a", "b  "}`). A negative value or `nil` means unlimited, and a limit above the number of separators has no effect.
- `chars` is a set of bytes stripped from either end, not a prefix, suffix, or pattern. An empty `chars` removes nothing.

`table.dedup` reads `values[1]` through `#values` with ordinary indexing, so `__len` and `__index` are honored, and returns a new sequence without a metatable. `nil` entries are skipped. Values are compared as raw table keys: `__eq` is ignored, `1` and `1.0` are duplicates, and every NaN is kept. Lengths above 1,000,000 raise an error.


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

The CLI configures host capabilities; Zig embedders opt in. `io.tmpfile` and `os.tmpname` create synthetic names/handles; a writable temporary handle still uses the filesystem capability when flushed or closed.

File reads share one size limit, 256 MiB by default (`limits.max_file_bytes` in the Zig API). Failures follow C Lua: `io.open` returns `nil, "path: No such file or directory", 2`, and `io.lines`/`io.input` raise `cannot open file 'path' (No such file or directory)`. Opening a directory for reading succeeds, and reads then fail with `Is a directory`.

`os.date` uses the C locale and supports the C99 conversions, including `E` and `O` modifiers. Without `!`, it and `os.time(table)` use the clock capability's local time zone. With the system clock that is `TZ` or `/etc/localtime`. A `fixed_local` clock uses its offset, and other fixed or disabled clocks use UTC. `os.date("*t")` sets `isdst`. Negative timestamps work. `os.clock` reports process CPU time with the system clock and `0` with a disabled or fixed clock.

`io.popen` buffers whole commands. Read mode runs the command when the handle opens; write mode runs it with the written bytes when the handle closes. `close` returns the command status like `os.execute`. Child processes inherit the host's stdio, as C `popen` and `system` do.

`os.exit` stops the state with `error.LuaExit`, which `pcall` cannot catch. The CLI exits with the requested status. `os.exit(code, true)` first runs pending to-be-closed variables. Embedders read the code with `State.exitRequest`; the host process keeps running.

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

JSON and TOML integer literals decode as Lua integers, literals with a fraction or exponent as floats, and MessagePack integer types as integers. Integers outside the 64-bit signed range raise an error rather than becoming floats (for example `json.read("9223372036854775808")`, a TOML integer overflow, or a MessagePack `uint64` above `math.maxinteger`). A JSON float literal too large for a double, such as `1e400`, decodes as `math.huge` and therefore cannot be written back.

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
