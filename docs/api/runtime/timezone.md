# runtime.timezone

## Navigation

- [API Index](../README.md)
- Parent: [runtime](../runtime.md)

<details>
<summary>All documents</summary>

- [root](../root.md)
- [frontend](../frontend.md)
- [errors](../errors.md)
- [frontend.source](../frontend/source.md)
- [frontend.token](../frontend/token.md)
- [frontend.diagnostic](../frontend/diagnostic.md)
- [frontend.lexer](../frontend/lexer.md)
- [frontend.ast](../frontend/ast.md)
- [frontend.parser](../frontend/parser.md)
- [compile](../compile.md)
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
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.host](../runtime/host.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.io](../runtime/io.md)
- [runtime.load](../runtime/load.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.index](../runtime/index.md)
- [runtime.operators](../runtime/operators.md)
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
- [stdlib.static_strings](../stdlib/static_strings.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.budget](../runtime/budget.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [runtime.native_fn](../runtime/native_fn.md)
- [compile.compiler](../compile/compiler.md)
- [compile.fold](../compile/fold.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
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
- [api.coroutine](../api/coroutine.md)
- [api.snapshot](../api/snapshot.md)
- [api.memory_limit](../api/memory_limit.md)
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
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.parallel](../testing/parallel.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Overview

Local-time support for the clock capability: civil-date arithmetic,
POSIX TZ rules, and TZif zone files parsed with `std.tz`.

## Functions

- [daysFromCivil](#fn-daysfromcivil)
- [civilFromDays](#fn-civilfromdays)
- [isLeapYear](#fn-isleapyear)
- [weekday](#fn-weekday)
- [localToUtc](#fn-localtoutc)

## Types

- [LocalOffset](#type-localoffset)
- [Civil](#type-civil)
- [PosixRule](#type-posixrule)
- [Zone](#type-zone)

## Constants

- [seconds_per_day](#const-seconds_per_day)

<a id="const-seconds_per_day"></a>

## seconds_per_day

```zig
pub const seconds_per_day: i64 = 86400;
```

<a id="type-localoffset"></a>

## LocalOffset

Local-time offset for one instant, in seconds east of UTC.

```zig
pub const LocalOffset = struct {
    offset: i32 = 0,
    is_dst: bool = false,
    /// Zone abbreviation, borrowed from the zone that produced it.
    name: ?[]const u8 = null,
};
```

<a id="type-civil"></a>

## Civil

```zig
pub const Civil = struct {
    year: i64,
    /// 1-12.
    month: u8,
    /// 1-31.
    day: u8,
};
```

<a id="fn-daysfromcivil"></a>

## daysFromCivil

Days since 1970-01-01 for a proleptic Gregorian date.

```zig
pub fn daysFromCivil(year: i64, month: i64, day: i64) i64
```

<a id="fn-civilfromdays"></a>

## civilFromDays

```zig
pub fn civilFromDays(days: i64) Civil
```

References: [`Civil`](#type-civil)

<a id="fn-isleapyear"></a>

## isLeapYear

```zig
pub fn isLeapYear(year: i64) bool
```

<a id="fn-weekday"></a>

## weekday

Day of week for days since the epoch, with Sunday as 0.

```zig
pub fn weekday(days: i64) u8
```

<a id="type-posixrule"></a>

## PosixRule

A POSIX TZ rule such as `EST5EDT,M3.2.0,M11.1.0`.

```zig
pub const PosixRule = struct {
    std_name: Name,
    /// Standard offset in seconds east of UTC.
    std_offset: i32,
    dst: ?Dst = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Name](#type-posixrule-name) |  |  |  |
| [Dst](#type-posixrule-dst) |  |  |  |
| [Transition](#type-posixrule-transition) |  |  |  |
| [parse](#fn-posixrule-parse) | `text: []const u8` | `?PosixRule` |  |
| [offsetAt](#fn-posixrule-offsetat) | `self: *const PosixRule, timestamp: i64` | `LocalOffset` |  |

<a id="type-posixrule-name"></a>

### PosixRule.Name

```zig
pub const Name = struct {
    bytes: [16]u8 = undefined,
    len: u8 = 0,
};
```

<a id="type-posixrule-dst"></a>

### PosixRule.Dst

```zig
pub const Dst = struct {
    name: Name,
    offset: i32,
    start: Transition,
    end: Transition,
};
```

<a id="type-posixrule-transition"></a>

### PosixRule.Transition

```zig
pub const Transition = struct {
    kind: enum { julian_no_leap, julian_zero, month_week_day },
    /// Julian day, or month for `month_week_day`.
    a: u16,
    /// Week (1-5) for `month_week_day`.
    b: u8 = 0,
    /// Weekday (0-6, Sunday = 0) for `month_week_day`.
    c: u8 = 0,
    /// Local time of day in seconds; may be negative or exceed one day.
    time: i32 = 2 * 3600,
};
```

<a id="fn-posixrule-parse"></a>

### PosixRule.parse

```zig
pub fn parse(text: []const u8) ?PosixRule
```

References: [`PosixRule`](#type-posixrule)

<a id="fn-posixrule-offsetat"></a>

### PosixRule.offsetAt

```zig
pub fn offsetAt(self: *const PosixRule, timestamp: i64) LocalOffset
```

References: [`PosixRule`](#type-posixrule), [`LocalOffset`](#type-localoffset)

<a id="type-zone"></a>

## Zone

TZif transitions with an optional POSIX footer, or a POSIX rule alone.

```zig
pub const Zone = struct {
    allocator: std.mem.Allocator,
    transitions: []const Transition = &.{},
    types: []const Type = &.{},
    rule: ?PosixRule = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Transition](#type-zone-transition) |  |  |  |
| [Type](#type-zone-type) |  |  |  |
| [utc](#fn-zone-utc) | `allocator: std.mem.Allocator` | `Zone` |  |
| [fromRule](#fn-zone-fromrule) | `allocator: std.mem.Allocator, text: []const u8` | `?Zone` |  |
| [parseTzif](#fn-zone-parsetzif) | `allocator: std.mem.Allocator, bytes: []const u8` | `!Zone` |  |
| [deinit](#fn-zone-deinit) | `self: *Zone` | `void` |  |
| [offsetAt](#fn-zone-offsetat) | `self: *const Zone, timestamp: i64` | `LocalOffset` |  |

<a id="type-zone-transition"></a>

### Zone.Transition

```zig
pub const Transition = struct {
    at: i64,
    type_index: u8,
};
```

<a id="type-zone-type"></a>

### Zone.Type

```zig
pub const Type = struct {
    offset: i32,
    is_dst: bool,
    name: [7]u8 = @splat(0),
    name_len: u8 = 0,
};
```

<a id="fn-zone-utc"></a>

### Zone.utc

```zig
pub fn utc(allocator: std.mem.Allocator) Zone
```

References: [`Zone`](#type-zone)

<a id="fn-zone-fromrule"></a>

### Zone.fromRule

```zig
pub fn fromRule(allocator: std.mem.Allocator, text: []const u8) ?Zone
```

References: [`Zone`](#type-zone)

<a id="fn-zone-parsetzif"></a>

### Zone.parseTzif

```zig
pub fn parseTzif(allocator: std.mem.Allocator, bytes: []const u8) !Zone
```

References: [`Zone`](#type-zone)

<a id="fn-zone-deinit"></a>

### Zone.deinit

```zig
pub fn deinit(self: *Zone) void
```

References: [`Zone`](#type-zone)

<a id="fn-zone-offsetat"></a>

### Zone.offsetAt

```zig
pub fn offsetAt(self: *const Zone, timestamp: i64) LocalOffset
```

References: [`Zone`](#type-zone), [`LocalOffset`](#type-localoffset)

<a id="fn-localtoutc"></a>

## localToUtc

Converts local wall-clock seconds to a Unix timestamp like `mktime`;
a non-null `is_dst` prefers an offset with that daylight-saving state.

```zig
pub fn localToUtc(context: anytype, comptime offsetAt: fn (@TypeOf(context), i64) anyerror!LocalOffset, local: i64, is_dst: ?bool) !i64
```

References: [`LocalOffset`](#type-localoffset)

