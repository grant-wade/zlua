# runtime.table_index

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
- [runtime.table_index](../runtime/table_index.md)
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
- [runtime.address_index](../runtime/address_index.md)
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

## Functions

- [hashKey](#fn-hashkey)
- [foldHash](#fn-foldhash)
- [hashStringKey](#fn-hashstringkey)
- [keysEqual](#fn-keysequal)
- [stringsEqual](#fn-stringsequal)

## Types

- [EntryIndex](#type-entryindex)

<a id="type-entryindex"></a>

## EntryIndex

Open-addressed index from hash-part keys to positions in `Table.entries`.
Slots keep 32 hash bits so most probes never touch the entry they name.

```zig
pub const EntryIndex = struct {
    slots: []Slot = &.{},
    count: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Slot](#type-entryindex-slot) |  |  |  |
| [deinit](#fn-entryindex-deinit) | `self: *EntryIndex, allocator: std.mem.Allocator` | `void` |  |
| [capacity](#fn-entryindex-capacity) | `self: *const EntryIndex` | `usize` |  |
| [clone](#fn-entryindex-clone) | `self: *const EntryIndex, allocator: std.mem.Allocator` | `!EntryIndex` |  |
| [clearRetainingCapacity](#fn-entryindex-clearretainingcapacity) | `self: *EntryIndex` | `void` |  |
| [find](#fn-entryindex-find) | `self: *const EntryIndex, entries: []const TableEntry, key: Value, hash: u32` | `?usize` |  |
| [ensureTotalCapacity](#fn-entryindex-ensuretotalcapacity) | `self: *EntryIndex, allocator: std.mem.Allocator, count: usize` | `!void` |  |
| [ensureUnusedCapacity](#fn-entryindex-ensureunusedcapacity) | `self: *EntryIndex, allocator: std.mem.Allocator, extra: usize` | `!void` |  |
| [insertAssumeCapacity](#fn-entryindex-insertassumecapacity) | `self: *EntryIndex, hash: u32, entry_index: usize` | `void` | The key must be absent and capacity reserved. |
| [rebuild](#fn-entryindex-rebuild) | `self: *EntryIndex, allocator: std.mem.Allocator, entries: []const TableEntry` | `!void` | Reindexes &#96;entries&#96; from scratch, keeping capacity when it suffices. |

<a id="type-entryindex-slot"></a>

### EntryIndex.Slot

```zig
pub const Slot = struct {
    hash: u32,
    /// Entry position plus one; zero marks an empty slot.
    entry: u32,
};
```

<a id="fn-entryindex-deinit"></a>

### EntryIndex.deinit

```zig
pub fn deinit(self: *EntryIndex, allocator: std.mem.Allocator) void
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-entryindex-capacity"></a>

### EntryIndex.capacity

```zig
pub inline fn capacity(self: *const EntryIndex) usize
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-entryindex-clone"></a>

### EntryIndex.clone

```zig
pub fn clone(self: *const EntryIndex, allocator: std.mem.Allocator) !EntryIndex
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-entryindex-clearretainingcapacity"></a>

### EntryIndex.clearRetainingCapacity

```zig
pub fn clearRetainingCapacity(self: *EntryIndex) void
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-entryindex-find"></a>

### EntryIndex.find

```zig
pub inline fn find(self: *const EntryIndex, entries: []const TableEntry, key: Value, hash: u32) ?usize
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-entryindex-ensuretotalcapacity"></a>

### EntryIndex.ensureTotalCapacity

```zig
pub fn ensureTotalCapacity(self: *EntryIndex, allocator: std.mem.Allocator, count: usize) !void
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-entryindex-ensureunusedcapacity"></a>

### EntryIndex.ensureUnusedCapacity

```zig
pub inline fn ensureUnusedCapacity(self: *EntryIndex, allocator: std.mem.Allocator, extra: usize) !void
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-entryindex-insertassumecapacity"></a>

### EntryIndex.insertAssumeCapacity

The key must be absent and capacity reserved.

```zig
pub inline fn insertAssumeCapacity(self: *EntryIndex, hash: u32, entry_index: usize) void
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-entryindex-rebuild"></a>

### EntryIndex.rebuild

Reindexes `entries` from scratch, keeping capacity when it suffices.

```zig
pub fn rebuild(self: *EntryIndex, allocator: std.mem.Allocator, entries: []const TableEntry) !void
```

References: [`EntryIndex`](#type-entryindex)

<a id="fn-hashkey"></a>

## hashKey

```zig
pub inline fn hashKey(key: Value) u32
```

<a id="fn-foldhash"></a>

## foldHash

```zig
pub inline fn foldHash(hash: u64) u32
```

<a id="fn-hashstringkey"></a>

## hashStringKey

```zig
pub inline fn hashStringKey(bytes: []const u8) u32
```

<a id="fn-keysequal"></a>

## keysEqual

```zig
pub inline fn keysEqual(stored: Value, key: Value) bool
```

<a id="fn-stringsequal"></a>

## stringsEqual

```zig
pub inline fn stringsEqual(lhs: []const u8, rhs: []const u8) bool
```

