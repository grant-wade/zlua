# runtime.rollback

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
- [compile.compiler](../compile/compiler.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
- [runtime](../runtime.md)
- [runtime.chunk](../runtime/chunk.md)
- [runtime.types](../runtime/types.md)
- [runtime.value](../runtime/value.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.state](../runtime/state.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.host](../runtime/host.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [stdlib.table](../stdlib/table.md)
- [stdlib.string](../stdlib/string.md)
- [stdlib.math](../stdlib/math.md)
- [stdlib.utf8](../stdlib/utf8.md)
- [stdlib.coroutine](../stdlib/coroutine.md)
- [stdlib.debug](../stdlib/debug.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.io](../stdlib/io.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [runtime.snapshot](../runtime/snapshot.md)
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
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Overview

Worker-local rollback. Retained storage is deliberately absent from GC roots.

## Functions

- [Record](#fn-record)
- [touch](#fn-touch)
- [tableWritable](#fn-tablewritable)
- [closureWritable](#fn-closurewritable)
- [threadWritable](#fn-threadwritable)
- [userdataWritable](#fn-userdatawritable)
- [copyPayload](#fn-copypayload)
- [retainCollected](#fn-retaincollected)

## Types

- [Journal](#type-journal)

<a id="fn-record"></a>

## Record

```zig
pub fn Record(comptime T: type) type
```

<a id="fn-touch"></a>

## touch

```zig
pub fn touch(object: anytype) void
```

<a id="fn-tablewritable"></a>

## tableWritable

```zig
pub fn tableWritable(table: *types.Table) !void
```

<a id="fn-closurewritable"></a>

## closureWritable

```zig
pub fn closureWritable(closure: *types.Closure) !void
```

<a id="fn-threadwritable"></a>

## threadWritable

```zig
pub fn threadWritable(thread: *types.Thread) !void
```

<a id="fn-userdatawritable"></a>

## userdataWritable

```zig
pub fn userdataWritable(userdata: *types.Userdata) !void
```

<a id="fn-copypayload"></a>

## copyPayload

```zig
pub fn copyPayload(a: std.mem.Allocator, lifetime: ?*types.AllocatorLifetime, p: *types.UserdataPayload) !*types.UserdataPayload
```

<a id="type-journal"></a>

## Journal

```zig
pub const Journal = struct {
    allocator: std.mem.Allocator,
    saved: State,
    tables: []Record(types.Table) = &.{},
    closures: []Record(types.Closure) = &.{},
    upvalues: []Record(types.Upvalue) = &.{},
    threads: []Record(types.Thread) = &.{},
    userdata: []Record(types.Userdata) = &.{},
    dirty: std.ArrayList(*Header) = .empty,
    eager: std.ArrayList(*Record(types.Userdata)) = .empty,
    new_objects: std.AutoHashMap(usize, Allocation),
    registries_detached: bool = false,
    output_detached: bool = false,
    /// Counts logical restored records, independently of the size of the heap.
    last_restored_objects: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [create](#fn-journal-create) | `state: *State, pristine: *const State` | `!*Journal` |  |
| [attach](#fn-journal-attach) | `self: *Journal, state: *State` | `void` |  |
| [prepareAllocation](#fn-journal-prepareallocation) | `self: *Journal, state: *State` | `!void` |  |
| [allocated](#fn-journal-allocated) | `self: *Journal, comptime field: []const u8, item: anytype` | `void` |  |
| [freed](#fn-journal-freed) | `self: *Journal, address: usize` | `void` |  |
| [detachRegistries](#fn-journal-detachregistries) | `self: *Journal, state: *State` | `!void` |  |
| [outputWritable](#fn-journal-outputwritable) | `self: *Journal, state: *State` | `!void` |  |
| [prepareCollection](#fn-journal-preparecollection) | `self: *Journal, state: *State` | `!void` | Called before GC enters its infallible destructive phases. |
| [keepString](#fn-journal-keepstring) | `self: *Journal, bytes: []const u8` | `bool` |  |
| [prepareReset](#fn-journal-preparereset) | `self: *Journal` | `![]*types.UserdataPayload` |  |
| [reset](#fn-journal-reset) | `self: *Journal, state: *State, prepared: []*types.UserdataPayload` | `void` |  |
| [abandon](#fn-journal-abandon) | `self: *Journal, state: *State` | `void` | End tracking while preserving the current logical state. Capture and destruction may traverse the baseline; reset only walks dirty records. |

<a id="fn-journal-create"></a>

### Journal.create

```zig
pub fn create(state: *State, pristine: *const State) !*Journal
```

References: [`Journal`](#type-journal)

<a id="fn-journal-attach"></a>

### Journal.attach

```zig
pub fn attach(self: *Journal, state: *State) void
```

References: [`Journal`](#type-journal)

<a id="fn-journal-prepareallocation"></a>

### Journal.prepareAllocation

```zig
pub fn prepareAllocation(self: *Journal, state: *State) !void
```

References: [`Journal`](#type-journal)

<a id="fn-journal-allocated"></a>

### Journal.allocated

```zig
pub fn allocated(self: *Journal, comptime field: []const u8, item: anytype) void
```

References: [`Journal`](#type-journal)

<a id="fn-journal-freed"></a>

### Journal.freed

```zig
pub fn freed(self: *Journal, address: usize) void
```

References: [`Journal`](#type-journal)

<a id="fn-journal-detachregistries"></a>

### Journal.detachRegistries

```zig
pub fn detachRegistries(self: *Journal, state: *State) !void
```

References: [`Journal`](#type-journal)

<a id="fn-journal-outputwritable"></a>

### Journal.outputWritable

```zig
pub fn outputWritable(self: *Journal, state: *State) !void
```

References: [`Journal`](#type-journal)

<a id="fn-journal-preparecollection"></a>

### Journal.prepareCollection

Called before GC enters its infallible destructive phases.

```zig
pub fn prepareCollection(self: *Journal, state: *State) !void
```

References: [`Journal`](#type-journal)

<a id="fn-journal-keepstring"></a>

### Journal.keepString

```zig
pub fn keepString(self: *Journal, bytes: []const u8) bool
```

References: [`Journal`](#type-journal)

<a id="fn-journal-preparereset"></a>

### Journal.prepareReset

```zig
pub fn prepareReset(self: *Journal) ![]*types.UserdataPayload
```

References: [`Journal`](#type-journal)

<a id="fn-journal-reset"></a>

### Journal.reset

```zig
pub fn reset(self: *Journal, state: *State, prepared: []*types.UserdataPayload) void
```

References: [`Journal`](#type-journal)

<a id="fn-journal-abandon"></a>

### Journal.abandon

End tracking while preserving the current logical state. Capture and
destruction may traverse the baseline; reset only walks dirty records.

```zig
pub fn abandon(self: *Journal, state: *State) void
```

References: [`Journal`](#type-journal)

<a id="fn-retaincollected"></a>

## retainCollected

```zig
pub fn retainCollected(object: anytype) bool
```

