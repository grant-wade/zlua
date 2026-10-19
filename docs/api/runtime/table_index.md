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
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.table_index](../runtime/table_index.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.operators](../runtime/operators.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.io](../runtime/io.md)
- [runtime.host](../runtime/host.md)
- [runtime.load](../runtime/load.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.upvalue](../runtime/upvalue.md)
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
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.budget](../runtime/budget.md)
- [runtime.object_pool](../runtime/object_pool.md)
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
- [testing.bench.system](../testing/bench/system.md)
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

## Types

- [HashPart](#type-hashpart)

<a id="type-hashpart"></a>

## HashPart

A table's hash part: this header, then `capacity` entries in insertion order, then `slot_count` index slots.

```zig
pub const HashPart = struct {
    len: u32 align(@alignOf(TableEntry)) = 0,
    capacity: u32,
    slot_count: u32,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Slot](#type-hashpart-slot) |  |  |  |
| [linear_limit](#const-hashpart-linear_limit) |  |  |  |
| [create](#fn-hashpart-create) | `allocator: std.mem.Allocator, capacity: u32` | `!*HashPart` |  |
| [destroy](#fn-hashpart-destroy) | `self: *HashPart, allocator: std.mem.Allocator` | `void` |  |
| [clone](#fn-hashpart-clone) | `self: *const HashPart, allocator: std.mem.Allocator` | `!*HashPart` |  |
| [allocationBytes](#fn-hashpart-allocationbytes) | `capacity: u32` | `usize` |  |
| [capacityFor](#fn-hashpart-capacityfor) | `count: usize` | `!u32` | The largest capacity of at least &#96;count&#96; that fits the same power-of-two size and keeps small parts unindexed. |
| [entries](#fn-hashpart-entries) | `self: *const HashPart` | `[]TableEntry` |  |
| [slots](#fn-hashpart-slots) | `self: *const HashPart` | `[]Slot` |  |
| [find](#fn-hashpart-find) | `self: *const HashPart, key: Value` | `?usize` |  |
| [findBytes](#fn-hashpart-findbytes) | `self: *const HashPart, key: []const u8, hash: u32` | `?usize` |  |
| [appendAssumeCapacity](#fn-hashpart-appendassumecapacity) | `self: *HashPart, key: Value, value: Value` | `void` | &#96;key&#96; must be absent and &#96;len&#96; below &#96;capacity&#96;. |
| [reindex](#fn-hashpart-reindex) | `self: *HashPart` | `void` | Restores the index after entries were removed, moved, or copied in. |

<a id="type-hashpart-slot"></a>

### HashPart.Slot

```zig
pub const Slot = struct {
    hash: u32,
    /// Entry position plus one; zero marks an empty slot.
    entry: u32,
};
```

<a id="const-hashpart-linear_limit"></a>

### HashPart.linear_limit

```zig
pub const linear_limit = 4;
```

<a id="fn-hashpart-create"></a>

### HashPart.create

```zig
pub fn create(allocator: std.mem.Allocator, capacity: u32) !*HashPart
```

References: [`HashPart`](#type-hashpart)

<a id="fn-hashpart-destroy"></a>

### HashPart.destroy

```zig
pub fn destroy(self: *HashPart, allocator: std.mem.Allocator) void
```

References: [`HashPart`](#type-hashpart)

<a id="fn-hashpart-clone"></a>

### HashPart.clone

```zig
pub fn clone(self: *const HashPart, allocator: std.mem.Allocator) !*HashPart
```

References: [`HashPart`](#type-hashpart)

<a id="fn-hashpart-allocationbytes"></a>

### HashPart.allocationBytes

```zig
pub fn allocationBytes(capacity: u32) usize
```

<a id="fn-hashpart-capacityfor"></a>

### HashPart.capacityFor

The largest capacity of at least `count` that fits the same power-of-two size and keeps small parts unindexed.

```zig
pub fn capacityFor(count: usize) !u32
```

<a id="fn-hashpart-entries"></a>

### HashPart.entries

```zig
pub inline fn entries(self: *const HashPart) []TableEntry
```

References: [`HashPart`](#type-hashpart)

<a id="fn-hashpart-slots"></a>

### HashPart.slots

```zig
pub inline fn slots(self: *const HashPart) []Slot
```

References: [`HashPart`](#type-hashpart)

<a id="fn-hashpart-find"></a>

### HashPart.find

```zig
pub inline fn find(self: *const HashPart, key: Value) ?usize
```

References: [`HashPart`](#type-hashpart)

<a id="fn-hashpart-findbytes"></a>

### HashPart.findBytes

```zig
pub inline fn findBytes(self: *const HashPart, key: []const u8, hash: u32) ?usize
```

References: [`HashPart`](#type-hashpart)

<a id="fn-hashpart-appendassumecapacity"></a>

### HashPart.appendAssumeCapacity

`key` must be absent and `len` below `capacity`.

```zig
pub inline fn appendAssumeCapacity(self: *HashPart, key: Value, value: Value) void
```

References: [`HashPart`](#type-hashpart)

<a id="fn-hashpart-reindex"></a>

### HashPart.reindex

Restores the index after entries were removed, moved, or copied in.

```zig
pub fn reindex(self: *HashPart) void
```

References: [`HashPart`](#type-hashpart)

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

