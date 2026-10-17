# api.snapshot

## Navigation

- [API Index](../README.md)
- Parent: [api](../api.md)

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
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Functions

- [create](#fn-create)
- [reset](#fn-reset)
- [writableBindings](#fn-writablebindings)
- [abandonRollbackMetadata](#fn-abandonrollbackmetadata)

## Types

- [Snapshot](#type-snapshot)
- [SnapshotBacking](#type-snapshotbacking)
- [RollbackMetadata](#type-rollbackmetadata)

<a id="type-snapshot"></a>

## Snapshot

Immutable, reference-counted VM snapshot. Separately retained handles may call `newState`
concurrently; bit copies do not retain ownership. Allocators must outlive every owner and
allow frees from any thread. Hookless userdata and host capabilities stay shared.

```zig
pub const Snapshot = struct {
    backing: *const SnapshotBacking,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [retain](#fn-snapshot-retain) | `self: *const Snapshot` | `Snapshot` | Returns a separately owned handle, e.g. to move to another thread. |
| [deinit](#fn-snapshot-deinit) | `self: *Snapshot` | `void` | Releases this handle; storage is freed after the final owner. |
| [newState](#fn-snapshot-newstate) | `self: *const Snapshot, state_allocator: std.mem.Allocator` | `!State` | Creates an independent State with this snapshot as its baseline; it keeps the snapshot alive. |

<a id="fn-snapshot-retain"></a>

### Snapshot.retain

Returns a separately owned handle, e.g. to move to another thread.

```zig
pub fn retain(self: *const Snapshot) Snapshot
```

References: [`Snapshot`](#type-snapshot)

<a id="fn-snapshot-deinit"></a>

### Snapshot.deinit

Releases this handle; storage is freed after the final owner.

```zig
pub fn deinit(self: *Snapshot) void
```

References: [`Snapshot`](#type-snapshot)

<a id="fn-snapshot-newstate"></a>

### Snapshot.newState

Creates an independent State with this snapshot as its baseline; it keeps the snapshot alive.

```zig
pub fn newState(self: *const Snapshot, state_allocator: std.mem.Allocator) !State
```

References: [`Snapshot`](#type-snapshot)

<a id="type-snapshotbacking"></a>

## SnapshotBacking

```zig
pub const SnapshotBacking = struct {
    allocator: std.mem.Allocator,
    lifetime: ?*runtime_types.AllocatorLifetime = null,
    references: std.atomic.Value(usize) = .init(1),
    image: State,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [retain](#fn-snapshotbacking-retain) | `self: *const SnapshotBacking` | `void` |  |
| [release](#fn-snapshotbacking-release) | `self: *const SnapshotBacking` | `void` |  |

<a id="fn-snapshotbacking-retain"></a>

### SnapshotBacking.retain

```zig
pub fn retain(self: *const SnapshotBacking) void
```

References: [`SnapshotBacking`](#type-snapshotbacking)

<a id="fn-snapshotbacking-release"></a>

### SnapshotBacking.release

```zig
pub fn release(self: *const SnapshotBacking) void
```

References: [`SnapshotBacking`](#type-snapshotbacking)

<a id="type-rollbackmetadata"></a>

## RollbackMetadata

```zig
pub const RollbackMetadata = struct {
    files: std.ArrayList(MemoryFile),
    owned: std.ArrayList(bool),
    callbacks: std.ArrayList(RegisteredCallback),
    error_value: ?runtime.Value,
    detached: bool = false,
};
```

<a id="fn-create"></a>

## create

```zig
pub fn create(state: *State, snapshot_allocator: std.mem.Allocator) !Snapshot
```

References: [`Snapshot`](#type-snapshot)

<a id="fn-reset"></a>

## reset

```zig
pub fn reset(state: *State) !void
```

<a id="fn-writablebindings"></a>

## writableBindings

```zig
pub fn writableBindings(state: *State) !void
```

<a id="fn-abandonrollbackmetadata"></a>

## abandonRollbackMetadata

```zig
pub fn abandonRollbackMetadata(state: *State) void
```

