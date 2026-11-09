# stdlib.datetime

## Navigation

- [API Index](../README.md)
- Parent: [stdlib](../stdlib.md)

<details>
<summary>All documents</summary>

- [root](../root.md)
- [api](../api.md)
- [api.analyze](../api/analyze.md)
- [compile](../compile.md)
- [errors](../errors.md)
- [frontend.source](../frontend/source.md)
- [frontend.token](../frontend/token.md)
- [frontend](../frontend.md)
- [frontend.diagnostic](../frontend/diagnostic.md)
- [frontend.lexer](../frontend/lexer.md)
- [stack_guard](../stack_guard.md)
- [frontend.ast](../frontend/ast.md)
- [frontend.parser](../frontend/parser.md)
- [compile.resolver](../compile/resolver.md)
- [compile.bytecode](../compile/bytecode.md)
- [compile.proto](../compile/proto.md)
- [runtime.types](../runtime/types.md)
- [runtime](../runtime.md)
- [runtime.chunk](../runtime/chunk.md)
- [reflection](../reflection.md)
- [runtime.state](../runtime/state.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [runtime.call](../runtime/call.md)
- [runtime.budget](../runtime/budget.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.io](../runtime/io.md)
- [runtime.host](../runtime/host.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.table_index](../runtime/table_index.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.operators](../runtime/operators.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.load](../runtime/load.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.index](../runtime/index.md)
- [stdlib.table](../stdlib/table.md)
- [stdlib.string](../stdlib/string.md)
- [stdlib.string.format](../stdlib/string/format.md)
- [stdlib.string.pack](../stdlib/string/pack.md)
- [stdlib.string.pattern](../stdlib/string/pattern.md)
- [stdlib.math](../stdlib/math.md)
- [stdlib.utf8](../stdlib/utf8.md)
- [stdlib.coroutine](../stdlib/coroutine.md)
- [stdlib.debug](../stdlib/debug.md)
- [stdlib.io](../stdlib/io.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.data](../stdlib/data.md)
- [stdlib.datetime](../stdlib/datetime.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.object_pool](../runtime/object_pool.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [runtime.native_fn](../runtime/native_fn.md)
- [compile.compiler](../compile/compiler.md)
- [compile.fold](../compile/fold.md)
- [compile.disasm](../compile/disasm.md)
- [api.callbacks](../api/callbacks.md)
- [api.convert](../api/convert.md)
- [api.errors](../api/errors.md)
- [api.handle](../api/handle.md)
- [api.state](../api/state.md)
- [runtime.snapshot](../runtime/snapshot.md)
- [api.capabilities](../api/capabilities.md)
- [api.options](../api/options.md)
- [api.function](../api/function.md)
- [api.table](../api/table.md)
- [api.value](../api/value.md)
- [api.userdata](../api/userdata.md)
- [api.context](../api/context.md)
- [api.decode](../api/decode.md)
- [api.coroutine](../api/coroutine.md)
- [api.string](../api/string.md)
- [api.snapshot](../api/snapshot.md)
- [api.memory_limit](../api/memory_limit.md)
- [api.namespace](../api/namespace.md)
- [testing](../testing.md)
- [testing.clua](../testing/clua.md)
- [testing.bench_runner](../testing/bench_runner.md)
- [testing.bench.options](../testing/bench/options.md)
- [testing.bench.results](../testing/bench/results.md)
- [testing.bench.stats](../testing/bench/stats.md)
- [testing.bench.report](../testing/bench/report.md)
- [testing.bench.process](../testing/bench/process.md)
- [testing.bench.fixtures](../testing/bench/fixtures.md)
- [testing.bench.legacy_process](../testing/bench/legacy_process.md)
- [testing.bench.startup](../testing/bench/startup.md)
- [testing.bench.allocation](../testing/bench/allocation.md)
- [testing.bench.c_startup](../testing/bench/c_startup.md)
- [testing.bench.snapshots](../testing/bench/snapshots.md)
- [testing.bench.gc](../testing/bench/gc.md)
- [testing.bench.system](../testing/bench/system.md)
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.parallel](../testing/parallel.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.format_suite](../testing/format_suite.md)
- [testing.official_suite](../testing/official_suite.md)
- [testing.sandbox_runner](../testing/sandbox_runner.md)
- [testing.generators](../testing/generators.md)

</details>

## Functions

- [scan](#fn-scan)
- [parse](#fn-parse)
- [daysInMonth](#fn-daysinmonth)
- [isDateTime](#fn-isdatetime)
- [toLua](#fn-tolua)
- [fromTable](#fn-fromtable)
- [parseText](#fn-parsetext)
- [new](#fn-new)
- [unix](#fn-unix)
- [now](#fn-now)
- [tostring](#fn-tostring)
- [eq](#fn-eq)
- [lt](#fn-lt)
- [le](#fn-le)
- [sub](#fn-sub)
- [kindMethod](#fn-kindmethod)
- [unixMethod](#fn-unixmethod)
- [utc](#fn-utc)
- [atOffset](#fn-atoffset)
- [with](#fn-with)
- [add](#fn-add)
- [dateMethod](#fn-datemethod)
- [timeMethod](#fn-timemethod)
- [weekday](#fn-weekday)
- [yday](#fn-yday)
- [formatMethod](#fn-formatmethod)

## Types

- [DateTime](#type-datetime)
- [Date](#type-date)
- [Time](#type-time)
- [Failure](#type-failure)

## Constants

- [max_year](#const-max_year)
- [max_unix_seconds](#const-max_unix_seconds)

<a id="const-max_year"></a>

## max_year

Largest year magnitude a datetime may have.

```zig
pub const max_year = 1_000_000_000;
```

<a id="const-max_unix_seconds"></a>

## max_unix_seconds

Largest Unix-seconds magnitude accepted, about `max_year` years.

```zig
pub const max_unix_seconds: i64 = 31_556_952 * max_year;
```

<a id="type-datetime"></a>

## DateTime

A TOML date-time: an offset date-time, local date-time, local date, or local time.

```zig
pub const DateTime = struct {
    date: ?Date = null,
    time: ?Time = null,
    /// Minutes east of UTC. Only date-times with both a date and a time have one.
    offset: ?i16 = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Kind](#type-datetime-kind) |  |  |  |
| [kind](#fn-datetime-kind) | `self: DateTime` | `Kind` |  |
| [format](#fn-datetime-format) | `self: DateTime, writer: *std.Io.Writer` | `std.Io.Writer.Error!void` |  |
| [unixSeconds](#fn-datetime-unixseconds) | `self: DateTime` | `i64` | Seconds since the Unix epoch. The date-time must have an offset. |
| [fromUnix](#fn-datetime-fromunix) | `seconds: i64, nano: u32` | `DateTime` |  |

<a id="type-datetime-kind"></a>

### DateTime.Kind

```zig
pub const Kind = enum {
    datetime,
    local_datetime,
    date,
    time,
};
```

#### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [name](#fn-kind-name) | `self: Kind` | `[]const u8` |  |

<a id="fn-kind-name"></a>

#### Kind.name

```zig
pub fn name(self: Kind) []const u8
```

<a id="fn-datetime-kind"></a>

### DateTime.kind

```zig
pub fn kind(self: DateTime) Kind
```

References: [`DateTime`](#type-datetime)

<a id="fn-datetime-format"></a>

### DateTime.format

```zig
pub fn format(self: DateTime, writer: *std.Io.Writer) std.Io.Writer.Error!void
```

References: [`DateTime`](#type-datetime)

<a id="fn-datetime-unixseconds"></a>

### DateTime.unixSeconds

Seconds since the Unix epoch. The date-time must have an offset.

```zig
pub fn unixSeconds(self: DateTime) i64
```

References: [`DateTime`](#type-datetime)

<a id="fn-datetime-fromunix"></a>

### DateTime.fromUnix

```zig
pub fn fromUnix(seconds: i64, nano: u32) DateTime
```

References: [`DateTime`](#type-datetime)

<a id="type-date"></a>

## Date

```zig
pub const Date = struct {
    year: i64,
    month: u8,
    day: u8,
};
```

<a id="type-time"></a>

## Time

```zig
pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32 = 0,
};
```

<a id="type-failure"></a>

## Failure

Where and why `scan` stopped.

```zig
pub const Failure = struct {
    offset: usize,
    message: []const u8,
};
```

<a id="fn-scan"></a>

## scan

Scans a TOML date-time starting at `start`, which must hold a digit. Returns the value
and the offset just past it.

```zig
pub fn scan(input: []const u8, start: usize, failure: *Failure) error{Invalid}!struct { DateTime, usize }
```

References: [`Failure`](#type-failure), [`DateTime`](#type-datetime)

<a id="fn-parse"></a>

## parse

```zig
pub fn parse(text: []const u8, failure: *Failure) error{Invalid}!DateTime
```

References: [`Failure`](#type-failure), [`DateTime`](#type-datetime)

<a id="fn-daysinmonth"></a>

## daysInMonth

```zig
pub fn daysInMonth(year: i64, month: u8) u8
```

<a id="fn-isdatetime"></a>

## isDateTime

```zig
pub fn isDateTime(state: *State, table: *Table) bool
```

<a id="fn-tolua"></a>

## toLua

```zig
pub fn toLua(state: *State, value: DateTime) !Value
```

References: [`DateTime`](#type-datetime)

<a id="fn-fromtable"></a>

## fromTable

Reads the date-time fields of `table`, or returns the reason they are invalid.

```zig
pub fn fromTable(table: *Table) union(enum) { ok: DateTime, invalid: []const u8 }
```

References: [`DateTime`](#type-datetime)

<a id="fn-parsetext"></a>

## parseText

```zig
pub fn parseText(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-new"></a>

## new

```zig
pub fn new(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-unix"></a>

## unix

```zig
pub fn unix(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-now"></a>

## now

`datetime.now([offset | "local"])`.

```zig
pub fn now(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-tostring"></a>

## tostring

```zig
pub fn tostring(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-eq"></a>

## eq

```zig
pub fn eq(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-lt"></a>

## lt

```zig
pub fn lt(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-le"></a>

## le

```zig
pub fn le(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-sub"></a>

## sub

```zig
pub fn sub(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-kindmethod"></a>

## kindMethod

```zig
pub fn kindMethod(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-unixmethod"></a>

## unixMethod

```zig
pub fn unixMethod(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-utc"></a>

## utc

```zig
pub fn utc(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-atoffset"></a>

## atOffset

```zig
pub fn atOffset(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-with"></a>

## with

```zig
pub fn with(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-add"></a>

## add

```zig
pub fn add(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-datemethod"></a>

## dateMethod

```zig
pub fn dateMethod(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-timemethod"></a>

## timeMethod

```zig
pub fn timeMethod(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-weekday"></a>

## weekday

```zig
pub fn weekday(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-yday"></a>

## yday

```zig
pub fn yday(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-formatmethod"></a>

## formatMethod

```zig
pub fn formatMethod(state: *State, thread: *Thread, op: bytecode.Call) !void
```

