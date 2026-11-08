# Lua Libraries and Extensions

zlua targets Lua 5.5 and adds a few things on top: the `fs` library, data-format
libraries, and some string and table helpers. Keep in mind that opening a
library only installs its Lua-visible functions. Whether those functions can
actually touch the filesystem, environment, clock, processes, or I/O is
controlled separately by host capabilities.

## Library Selection

You choose which libraries a state gets with one of these selections:

| Selection | Libraries |
| --- | --- |
| `none` | No libraries; the global environment and `_G` still exist. |
| `base` | Base globals. |
| `safe` | Base, table, string, math, utf8, coroutine, json, toml, msgpack, csv, and datetime. |
| `full` | Safe plus io, os, debug, package, and fs. |
| Explicit set | Any combination of the libraries above. |

The CLI defaults to `full` with host access, while `zlua.State` defaults to
`safe` with sandboxed capabilities. Both accept a different selection:

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

The base library sets `_VERSION = "Lua 5.5"` and installs the usual core
functions:

```text
assert  collectgarbage  dofile  error  getmetatable  ipairs  load
loadfile  next  pairs  pcall  print  rawequal  rawget  rawlen  rawset
select  setmetatable  tonumber  tostring  type  warn  xpcall
```

A few of these deserve a note. `warn` follows Lua 5.5, including the `@on` and
`@off` control messages. Warnings start off, as in the CLI without `-W`, and
once enabled they print to stderr as `Lua warning: <message>`. `xpcall` runs its
message handler at the point of the error, before any to-be-closed variables
close. `loadfile` and `dofile` read through the filesystem capability, or from
stdin when no file name is given. `package.config` and the default searchers use
`/` as the directory separator with memory and `host_dir` filesystems on every
OS. `load`, `loadfile`, `dofile`, and `require` accept binary chunks in the CLI,
and in embedded states with `Options.binary_chunks`.

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

Most of these are standard Lua. `table.create(nseq[, nrec])` may look like an
extension, but it is part of Lua 5.5. The zlua-specific additions are covered in
the next section.

`collectgarbage` supports Lua 5.5's incremental and generational modes, and
generational is the default. Use `collectgarbage("collect")` for a full
collection or `collectgarbage("step", bytes)` to advance one. Explicit
collection still works after `collectgarbage("stop")`. Memory counts and
collection timing may differ from C Lua. For controls on the host side, see
[Garbage Collection](embedding.md#garbage-collection).

### zlua Additions to Core Libraries

zlua adds four helpers to the `table` and `string` libraries:

| Function | Behavior |
| --- | --- |
| `table.dedup(values)` | Returns unique array elements in first-occurrence order using raw key equality; non-array fields are ignored. |
| `string.strip(value[, chars])` | Removes leading/trailing ASCII whitespace or bytes from `chars`. |
| `string.split(value[, separator[, maxsplit]])` | Splits from the left; omitted separator means ASCII whitespace. |
| `string.rsplit(value[, separator[, maxsplit]])` | Same operation starting from the right. |

The string helpers follow Python's `bytes.split`, `bytes.rsplit`, and
`bytes.strip`. The separator is plain text rather than a pattern, and a `nil`
separator splits on whitespace. `maxsplit` limits the number of splits, with a
negative or `nil` value meaning no limit. For `strip`, `chars` is treated as a
set of bytes.

`table.dedup` compares values the way raw table keys are compared, so `__eq` is
ignored and `1` and `1.0` count as duplicates. It reads up to `#values`, skips
`nil` entries, and raises `array too big` above 1,000,000 elements.

## Host-Facing Libraries

In an embedded state, opening `io`, `os`, `package`, or `fs` doesn't by itself
give Lua code any access to the host. Each operation needs the matching
capability:

| Operations | Capability |
| --- | --- |
| `io.read`, `io.write`, standard streams, `print` | I/O streams. |
| `io.open`, file methods, `loadfile`, `dofile`, filesystem `require` | Filesystem, plus `std.Io` for std-backed modes. |
| `os.time()` and `os.date()` without an explicit time, local time, `os.clock` | Clock; the system clock also needs `std.Io`. |
| `os.getenv` | Environment. |
| `os.execute`, `io.popen`, `os.exit` | Process; enabled mode also needs `std.Io`. Children get the `environment` map when one is set, and otherwise an empty environment. |
| `os.remove`, `os.rename` | Filesystem. |
| `fs.*` | Filesystem; std-backed modes also need `std.Io`. |

The CLI sets these capabilities up for you, whereas Zig embedders opt in to each
one.

### Files

File handles are `FILE*` userdata, as in C Lua. A failed `io.open` returns
`nil, "path: No such file or directory", 2`.

Writes are buffered in memory and count toward `max_memory`, and `io` file
handles can't grow a file past `max_file_bytes` (256 MiB by default). A write
past `max_memory` raises `not enough memory`. Other failed writes return
`nil, message, errno, count`. Writing to a handle not opened for writing returns
`nil, "Bad file descriptor", 9, 0`, and reading from one not opened for reading
returns `nil, "Bad file descriptor", 9`, or `nil, "(no extra info)", 0` on
Windows. When you close or flush a file explicitly with `close` or `flush`,
failures come back as `nil, message, errno`. Handles you don't close yourself
are still cleaned up: the collector flushes and closes unreachable ones, and
`State.deinit` closes any that remain open. These implicit closes ignore flush
failures.

The `io` library emulates `/dev/null` in every filesystem mode, and `/dev/full`
on Linux and FreeBSD. `fs.*` treats `/dev/null` as an ordinary path.
`io.tmpfile()` returns an in-memory file and needs no filesystem capability.

`os.tmpname()` needs a writable filesystem and raises without one. It creates an
empty file with a unique `lua_XXXXXX` name, under `host_cwd` in `TMPDIR` (read
through the environment capability) or `/tmp`, and at the root of other writable
filesystems.

### Time, Processes, and Native Libraries

`os.date` supports the C99 conversions. The clock capability decides local time
and what `os.clock` reports; see
[Clock and Process](embedding.md#clock-and-process).

`io.popen` runs the whole command in one go: in read mode when the handle opens,
and in write mode when it closes.

With process access granted, `os.exit` raises `error.LuaExit`, which `pcall`
can't catch. The CLI then exits with the requested status and runs `__gc`
finalizers, unless `os.exit` was called without `close`. An `os.exit` inside a
finalizer ends the CLI at that point, as in C Lua. With process access disabled,
it raises a catchable `process access disabled` error.

zlua doesn't load native libraries, so `package.loadlib` always returns
`nil, "dynamic libraries not enabled; check your Lua installation", "absent"`.

## Package Loading

Opening `package` installs `require`. If base isn't open, it also installs
`loadfile` and `dofile`. The package fields start with these defaults:

| Field | Default |
| --- | --- |
| `package.path` | `./?.lua;./?/init.lua` |
| `package.cpath` | Empty; native C modules are not loaded. |
| `package.searchers` | Preload, Lua file, C, and all-in-one searchers. A C library found on `package.cpath` fails to load. |
| `package.loaded` | Opened libraries, with the base library as `_G`, and already loaded modules. |
| `package.preload` | Host-preloaded modules. |

Loading Lua files with `require` needs a filesystem capability. If you want
module loading without host filesystem access, memory files give you that.

## Filesystem Extension

`fs` is zlua's filesystem library. It's included in `full`, left out of `safe`,
and always gated by the filesystem capability. When `fs` and `package` open
together, `require("fs")` returns the same table as the `fs` global.

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
| `exists(path[, options])` | False for a missing path; other failures return `nil, error`. `follow_symlinks` defaults to true. |
| `list(path[, options])` | Snapshot entries, sorted unless `sorted=false`. |
| `scandir(path)` | Callable, closable directory iterator. |
| `walk(path[, options])` | Recursive iterator with `max_depth` and `walker:skip()`. |
| `read(path[, options])` | Binary-safe whole-file read; `max_bytes` defaults to the 256 MiB file limit. |
| `write(path, bytes[, options])` | Supports `append`, `exclusive`, `atomic`, and `create_parents`. Fails past `max_file_bytes`. |
| `open(path[, mode])` | File handle with standard methods plus `stat`, `tell`, `truncate`, `path`, and `sync`, which is an alias for `flush`. |
| `open_dir(path)` | Closable directory with `entries`, `walk`, `open`, `stat`, `mkdir`, and `remove`. |
| `mkdir(path[, options])` | Options are `parents` and `exist_ok`. |
| `remove(path[, options])` | Options are `recursive` and `missing_ok`. |
| `copy(source, destination[, options])` | Options are `recursive` and `overwrite`. |
| `rename`, `move`, `touch` | Path mutation helpers; `move` copies and removes across devices. |

Iterator entries include `name`, `path`, `kind`, `inode`, and `depth`; `fs.list`
entries omit `depth`. Operational failures in `fs.*` functions and the `stat`
and `truncate` methods return `nil` plus a structured error, standard file
methods return `io`-style results, and argument and iterator failures raise.

For pure path manipulation, `fs.path` provides lexical `join`, `normalize`,
`basename`, `dirname`, `extension`, `stem`, `is_absolute`, `relative`, and
`separator` helpers. None of them touch the filesystem. `relative` raises when
only one path is absolute, or when the first path climbs above their shared
base.

## Data Formats

`json`, `toml`, `msgpack`, and `csv` are available in both `safe` and `full`.
With `package` open, `require("json")` and the other names return the existing
global tables through `package.loaded`.

The four libraries share some conventions. Every reader accepts either a string
(bytes for MessagePack) or a Lua file handle, and file input is consumed from
the current position to EOF. `json.null`, `msgpack.null`, and `csv.null` are
one shared value.

Errors start with the library and operation name. Reader errors then give the
line and column, or the byte offset for MessagePack. Writer errors give the
path to the value, such as `$.servers[2].port`:

```text
json.read: line 3, column 7: expected ':' after object key, found '2'
json.write: at $.servers[2].port: cannot encode a function value
```

The JSON, TOML, and MessagePack writers also agree on how a Lua table maps to
the output:

- Sequential positive integer keys become arrays.
- Lua floats stay floats: JSON, TOML, and CSV print `2.0` and `1e300`.
- String-keyed tables and empty tables become objects/maps.
- Cycles, sparse arrays, mixed array/object tables, unsupported values, and
  non-string object keys are rejected.
- JSON and CSV reject non-finite numbers. TOML writes `inf`, `-inf`, and `nan`.
- Only MessagePack can write extension values.

Readers and writers reject nesting deeper than 64 levels. Integers outside the
64-bit signed range raise an error rather than quietly becoming floats.

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
| `toml.read(input)` | Decodes TOML 1.1. Dates and times become `datetime` values. |
| `toml.write(table[, options])` | Encodes a table. `layout` accepts `inline_tables`/`inline` or `sections`. |

### MessagePack

```lua
local bytes = msgpack.write({ 1, msgpack.null, "ok" })
assert(msgpack.read(bytes)[2] == msgpack.null)
```

| Member | Behavior |
| --- | --- |
| `msgpack.read(input)` | Decodes exactly one complete value and rejects trailing bytes. `str` and `bin` become Lua strings, timestamps become `datetime` values, and other extension types become extension values. Map keys must be `str` or `bin`. A `uint64` above the integer range becomes a float. |
| `msgpack.write(value)` | Uses `str` for UTF-8 strings and `bin` otherwise, for values and map keys. Floats use `float32` when it holds the value exactly. |
| `msgpack.null` | Sentinel for MessagePack nil. Lua `nil` also encodes as nil. |
| `msgpack.extension(type, data)` | Creates an extension value with fields `type` (-128 to 127, except the timestamp type -1) and `data`. |

### CSV

```lua
local rows = csv.read("name,age\r\nAda,37\r\nBob,")
assert(rows[2].age == csv.null)

local text = csv.write(rows, { record_terminator = "lf" })
```

`csv.read(input[, options])` returns an array of row tables. Cells are strings.
An empty cell is `csv.null`, and a quoted empty cell (`""`) is `""`. With `header=false`, the keys are strings
starting at `"0"`.

`csv.write(rows[, options])` needs at least one row with named fields. It takes
its schema and field order from the first row and flattens nested objects into
dot-separated columns. Later rows may omit fields, but they can't introduce new
ones, and nested arrays are rejected. Cells may be nil/null, booleans, finite
numbers, or strings.

Both functions accept these options:

| CSV option | Values / default |
| --- | --- |
| `delimiter` | `comma`/`,` (default) or `tab`/`tsv`/tab. |
| `header` | Boolean, default true. |
| `record_terminator` | `crlf`/`\r\n` (default) or `lf`/`\n`. |
| `final_record_terminator` | Boolean, default false. |

`csv.read` accepts both line endings whatever these last two options say.

## Datetime

`datetime` is available in both `safe` and `full`. `datetime.now` exists only
when `os` is open.

A datetime is a table with a protected metatable. Its fields follow
`os.date("*t")`, so `os.time` accepts it, and which fields are present gives
its kind:

| Kind | Fields |
| --- | --- |
| `datetime` | `year`, `month`, `day`, `hour`, `min`, `sec`, `nsec`, and `offset` in minutes east of UTC. |
| `local datetime` | The same without `offset`. |
| `date` | `year`, `month`, `day`. |
| `time` | `hour`, `min`, `sec`, `nsec`. |

```lua
local launch = datetime.parse("1979-05-27T07:32:00-07:00")
print(launch.year, launch:kind(), launch:unix())  --> 1979  datetime  296663520

local due = launch:add{ months = 1, days = 3 }
print(due:utc(), due:format("%Y-%m-%d %H:%M"))    --> 1979-06-30T14:32:00Z  1979-06-30 07:32

local config = toml.read("deadline = 2026-11-07T17:00:00-08:00")
config.deadline = config.deadline:add{ weeks = 1 }
```

| Member | Behavior |
| --- | --- |
| `datetime.parse(text)` | Parses any kind in TOML/RFC 3339 form. Seconds are optional, and a space may separate the date and time. |
| `datetime.new(fields)` | Builds from fields. `min` and `sec` default to 0, and unknown fields such as `isdst` are ignored. |
| `datetime.unix(seconds[, nsec])` | A UTC datetime. A float's fraction becomes nanoseconds. |
| `datetime.now([offset])` | The current time from the state's clock, at UTC, at `offset` minutes, or at the local offset with `"local"`. |

| Method | Behavior |
| --- | --- |
| `d:kind()` | `"datetime"`, `"local datetime"`, `"date"`, or `"time"`. |
| `d:unix()` | Seconds and nanoseconds since the Unix epoch. Needs an offset. |
| `d:utc()`, `d:at_offset(minutes)` | The same instant at another offset. |
| `d:with(fields)` | A copy with some fields changed. |
| `d:add(amounts)` | Adds `years`, `months`, `weeks`, `days`, `hours`, `minutes`, `seconds`, and `nanoseconds`, each an integer and possibly negative. Months and years clamp to the end of the month, a date adds only whole days, and a time wraps at midnight. |
| `d:date()`, `d:time()` | The date or time part. |
| `d:weekday()`, `d:yday()` | ISO weekday (Monday is 1) and day of the year. |
| `d:format([pattern])` | `os.date` conversions plus `%f` for nanoseconds. Without a pattern it returns the same text as `tostring`. |

`tostring` gives RFC 3339 text. `==` compares instants for datetimes, so
`07:32-07:00` equals `14:32Z`, and compares fields for other kinds. Values of
different kinds are never equal. `<` and `<=` need values of the same kind, and
`a - b` gives the difference in seconds as a float.

Fields can be changed directly. A value with invalid fields raises an error when
it is used.

`toml.read` and `toml.write` read and write every kind, `msgpack.read` and
`msgpack.write` use datetimes for timestamps, and JSON and CSV write the text.

