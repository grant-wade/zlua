# runtime.gc

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

- [tableCapacityBytes](#fn-tablecapacitybytes)
- [tableGcBytes](#fn-tablegcbytes)
- [userdataBytes](#fn-userdatabytes)

## Types

- [Gc](#type-gc)

<a id="type-gc"></a>

## Gc

```zig
pub const Gc = struct {
    collecting: bool = false,
    stress_collect: bool = false,
    stress_step: bool = false,
    stress_mark: usize = 0,
    running: bool = true,
    mode: GcMode = .generational,
    params: GcParams = .{},
    next_total: usize = 0,
    known_total: usize = 0,
    epoch: u64 = 1,
    generation: u64 = 1,
    phase: types.GcPhase = .pause,
    cycle: types.GcCycle = .major,
    work: std.ArrayList(types.GcObject) = .empty,
    remembered: std.ArrayList(types.GcObject) = .empty,
    weak: std.ArrayList(*Table) = .empty,
    tables: std.ArrayList(*Table) = .empty,
    finalizers: std.ArrayList(types.FinalizerObject) = .empty,
    major_pending: bool = false,
    cycle_start_total: usize = 0,
    found_young: bool = false,
    old: types.GcGenerations = .{},
    sweep_cursor: usize = 0,
    major_base: usize = 0,
    work_done: usize = 0,
    minor_count: usize = 0,
    mark_all_stack_registers: bool = false,
    conservative_depth: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [reserveQueues](#fn-gc-reservequeues) | `gc: *Gc, extra: usize` | `!void` |  |
| [prepareRegistration](#fn-gc-prepareregistration) | `gc: *Gc, comptime field: []const u8` | `!void` |  |
| [registeredAllocation](#fn-gc-registeredallocation) | `gc: *Gc, comptime field: []const u8, item: anytype` | `void` |  |
| [forgetThread](#fn-gc-forgetthread) | `gc: *Gc, thread: *Thread` | `void` |  |
| [isOld](#fn-gc-isold) | `gc: *Gc, object: anytype` | `bool` |  |
| [rememberObject](#fn-gc-rememberobject) | `gc: *Gc, object: types.GcObject` | `void` |  |
| [propagate](#fn-gc-propagate) | `gc: *Gc, budget: usize` | `usize` |  |
| [noteAllocation](#fn-gc-noteallocation) | `gc: *Gc, bytes: usize` | `void` |  |
| [noteAllocationFreed](#fn-gc-noteallocationfreed) | `gc: *Gc, bytes: usize` | `void` |  |
| [refreshAllocationTotal](#fn-gc-refreshallocationtotal) | `gc: *Gc` | `usize` |  |
| [currentAllocationTotal](#fn-gc-currentallocationtotal) | `gc: *Gc` | `usize` |  |
| [noteTableCapacityDelta](#fn-gc-notetablecapacitydelta) | `gc: *Gc, table: *Table, old_capacity_bytes: usize` | `void` |  |
| [syncThreadStorage](#fn-gc-syncthreadstorage) | `gc: *Gc, thread: *Thread` | `void` |  |
| [collectGarbageValue](#fn-gc-collectgarbagevalue) | `gc: *Gc, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [autoStep](#fn-gc-autostep) | `gc: *Gc, thread: ?*Thread` | `!void` |  |
| [step](#fn-gc-step) | `gc: *Gc, thread: ?*Thread, conservative: bool` | `!bool` | A basic step bounds propagation by references and sweeping by objects. Atomic weak processing, large objects, and one finalizer can exceed the target. |
| [collect](#fn-gc-collect) | `gc: *Gc` | `!void` |  |
| [getParam](#fn-gc-getparam) | `gc: *const Gc, param: GcParam` | `i64` |  |
| [setParam](#fn-gc-setparam) | `gc: *Gc, param: GcParam, value: i64` | `void` |  |
| [collectWithFinalizers](#fn-gc-collectwithfinalizers) | `gc: *Gc, thread: ?*Thread` | `!void` |  |
| [shouldRunAuto](#fn-gc-shouldrunauto) | `gc: *Gc` | `bool` |  |
| [resetAutoThreshold](#fn-gc-resetautothreshold) | `gc: *Gc` | `void` |  |
| [normalizeBaseline](#fn-gc-normalizebaseline) | `gc: *Gc` | `void` |  |
| [markValue](#fn-gc-markvalue) | `gc: *Gc, value: Value` | `void` |  |
| [markString](#fn-gc-markstring) | `gc: *Gc, bytes: []const u8` | `void` |  |
| [writeTableBarrier](#fn-gc-writetablebarrier) | `gc: *Gc, table: *Table, key: Value, value: Value` | `void` |  |
| [writeBarrier](#fn-gc-writebarrier) | `gc: *Gc, parent: anytype, child: Value` | `void` |  |
| [checkUserdataFinalizer](#fn-gc-checkuserdatafinalizer) | `gc: *Gc, userdata: *Userdata` | `void` | Registers &#96;userdata&#96; for its metatable's &#96;__gc&#96; if needed, like &#96;luaC_checkfinalizer&#96;. File handles are registered at creation, so they finalize in creation order. |
| [removeRegistryItem](#fn-gc-removeregistryitem) | `gc: *Gc, comptime field: []const u8, index: usize` | `void` |  |
| [findStringAllocation](#fn-gc-findstringallocation) | `gc: *Gc, bytes: []const u8` | `?usize` |  |
| [isTrackedTable](#fn-gc-istrackedtable) | `gc: *Gc, table: *Table` | `bool` |  |
| [destroyTable](#fn-gc-destroytable) | `gc: *Gc, table: *Table` | `void` |  |
| [destroyUserdata](#fn-gc-destroyuserdata) | `gc: *Gc, userdata: *Userdata` | `void` |  |
| [destroyClosure](#fn-gc-destroyclosure) | `gc: *Gc, closure: *Closure` | `void` |  |
| [destroyThread](#fn-gc-destroythread) | `gc: *Gc, thread: *Thread` | `void` |  |
| [allocationStats](#fn-gc-allocationstats) | `gc: *const Gc` | `RuntimeAllocationStats` |  |
| [noteTableMetatableChanged](#fn-gc-notetablemetatablechanged) | `gc: *Gc, table: *Table, old_has_metatable: bool` | `void` |  |
| [setMode](#fn-gc-setmode) | `gc: *Gc, mode: GcMode` | `GcMode` |  |
| [runSteps](#fn-gc-runsteps) | `gc: *Gc, steps: usize` | `!bool` |  |
| [upvalueBarrier](#fn-gc-upvaluebarrier) | `gc: *Gc, closure: *Closure, upvalue: *Upvalue` | `void` |  |
| [threadBarrier](#fn-gc-threadbarrier) | `gc: *Gc, thread: *Thread, value: Value` | `void` |  |
| [runCloseFinalizers](#fn-gc-runclosefinalizers) | `gc: *Gc` | `void` | Runs pending finalizers as &#96;deinit&#96; does, keeping the state. Only for an idle host; later registrations are left for &#96;deinit&#96;. |

<a id="fn-gc-reservequeues"></a>

### Gc.reserveQueues

```zig
pub fn reserveQueues(gc: *Gc, extra: usize) !void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-prepareregistration"></a>

### Gc.prepareRegistration

```zig
pub fn prepareRegistration(gc: *Gc, comptime field: []const u8) !void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-registeredallocation"></a>

### Gc.registeredAllocation

```zig
pub fn registeredAllocation(gc: *Gc, comptime field: []const u8, item: anytype) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-forgetthread"></a>

### Gc.forgetThread

```zig
pub fn forgetThread(gc: *Gc, thread: *Thread) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-isold"></a>

### Gc.isOld

```zig
pub fn isOld(gc: *Gc, object: anytype) bool
```

References: [`Gc`](#type-gc)

<a id="fn-gc-rememberobject"></a>

### Gc.rememberObject

```zig
pub fn rememberObject(gc: *Gc, object: types.GcObject) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-propagate"></a>

### Gc.propagate

```zig
pub fn propagate(gc: *Gc, budget: usize) usize
```

References: [`Gc`](#type-gc)

<a id="fn-gc-noteallocation"></a>

### Gc.noteAllocation

```zig
pub fn noteAllocation(gc: *Gc, bytes: usize) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-noteallocationfreed"></a>

### Gc.noteAllocationFreed

```zig
pub fn noteAllocationFreed(gc: *Gc, bytes: usize) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-refreshallocationtotal"></a>

### Gc.refreshAllocationTotal

```zig
pub fn refreshAllocationTotal(gc: *Gc) usize
```

References: [`Gc`](#type-gc)

<a id="fn-gc-currentallocationtotal"></a>

### Gc.currentAllocationTotal

```zig
pub fn currentAllocationTotal(gc: *Gc) usize
```

References: [`Gc`](#type-gc)

<a id="fn-gc-notetablecapacitydelta"></a>

### Gc.noteTableCapacityDelta

```zig
pub fn noteTableCapacityDelta(gc: *Gc, table: *Table, old_capacity_bytes: usize) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-syncthreadstorage"></a>

### Gc.syncThreadStorage

```zig
pub fn syncThreadStorage(gc: *Gc, thread: *Thread) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-collectgarbagevalue"></a>

### Gc.collectGarbageValue

```zig
pub fn collectGarbageValue(gc: *Gc, thread: *Thread, op: bytecode.Call) !void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-autostep"></a>

### Gc.autoStep

```zig
pub fn autoStep(gc: *Gc, thread: ?*Thread) !void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-step"></a>

### Gc.step

A basic step bounds propagation by references and sweeping by objects.
Atomic weak processing, large objects, and one finalizer can exceed the target.

```zig
pub fn step(gc: *Gc, thread: ?*Thread, conservative: bool) !bool
```

References: [`Gc`](#type-gc)

<a id="fn-gc-collect"></a>

### Gc.collect

```zig
pub fn collect(gc: *Gc) !void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-getparam"></a>

### Gc.getParam

```zig
pub fn getParam(gc: *const Gc, param: GcParam) i64
```

References: [`Gc`](#type-gc)

<a id="fn-gc-setparam"></a>

### Gc.setParam

```zig
pub fn setParam(gc: *Gc, param: GcParam, value: i64) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-collectwithfinalizers"></a>

### Gc.collectWithFinalizers

```zig
pub fn collectWithFinalizers(gc: *Gc, thread: ?*Thread) !void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-shouldrunauto"></a>

### Gc.shouldRunAuto

```zig
pub fn shouldRunAuto(gc: *Gc) bool
```

References: [`Gc`](#type-gc)

<a id="fn-gc-resetautothreshold"></a>

### Gc.resetAutoThreshold

```zig
pub fn resetAutoThreshold(gc: *Gc) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-normalizebaseline"></a>

### Gc.normalizeBaseline

```zig
pub fn normalizeBaseline(gc: *Gc) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-markvalue"></a>

### Gc.markValue

```zig
pub fn markValue(gc: *Gc, value: Value) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-markstring"></a>

### Gc.markString

```zig
pub fn markString(gc: *Gc, bytes: []const u8) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-writetablebarrier"></a>

### Gc.writeTableBarrier

```zig
pub fn writeTableBarrier(gc: *Gc, table: *Table, key: Value, value: Value) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-writebarrier"></a>

### Gc.writeBarrier

```zig
pub fn writeBarrier(gc: *Gc, parent: anytype, child: Value) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-checkuserdatafinalizer"></a>

### Gc.checkUserdataFinalizer

Registers `userdata` for its metatable's `__gc` if needed, like `luaC_checkfinalizer`.
[File](../stdlib/io.md#type-file) handles are registered at creation, so they finalize in creation order.

```zig
pub fn checkUserdataFinalizer(gc: *Gc, userdata: *Userdata) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-removeregistryitem"></a>

### Gc.removeRegistryItem

```zig
pub fn removeRegistryItem(gc: *Gc, comptime field: []const u8, index: usize) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-findstringallocation"></a>

### Gc.findStringAllocation

```zig
pub fn findStringAllocation(gc: *Gc, bytes: []const u8) ?usize
```

References: [`Gc`](#type-gc)

<a id="fn-gc-istrackedtable"></a>

### Gc.isTrackedTable

```zig
pub fn isTrackedTable(gc: *Gc, table: *Table) bool
```

References: [`Gc`](#type-gc)

<a id="fn-gc-destroytable"></a>

### Gc.destroyTable

```zig
pub fn destroyTable(gc: *Gc, table: *Table) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-destroyuserdata"></a>

### Gc.destroyUserdata

```zig
pub fn destroyUserdata(gc: *Gc, userdata: *Userdata) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-destroyclosure"></a>

### Gc.destroyClosure

```zig
pub fn destroyClosure(gc: *Gc, closure: *Closure) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-destroythread"></a>

### Gc.destroyThread

```zig
pub fn destroyThread(gc: *Gc, thread: *Thread) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-allocationstats"></a>

### Gc.allocationStats

```zig
pub fn allocationStats(gc: *const Gc) RuntimeAllocationStats
```

References: [`Gc`](#type-gc)

<a id="fn-gc-notetablemetatablechanged"></a>

### Gc.noteTableMetatableChanged

```zig
pub fn noteTableMetatableChanged(gc: *Gc, table: *Table, old_has_metatable: bool) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-setmode"></a>

### Gc.setMode

```zig
pub fn setMode(gc: *Gc, mode: GcMode) GcMode
```

References: [`Gc`](#type-gc)

<a id="fn-gc-runsteps"></a>

### Gc.runSteps

```zig
pub fn runSteps(gc: *Gc, steps: usize) !bool
```

References: [`Gc`](#type-gc)

<a id="fn-gc-upvaluebarrier"></a>

### Gc.upvalueBarrier

```zig
pub fn upvalueBarrier(gc: *Gc, closure: *Closure, upvalue: *Upvalue) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-threadbarrier"></a>

### Gc.threadBarrier

```zig
pub fn threadBarrier(gc: *Gc, thread: *Thread, value: Value) void
```

References: [`Gc`](#type-gc)

<a id="fn-gc-runclosefinalizers"></a>

### Gc.runCloseFinalizers

Runs pending finalizers as `deinit` does, keeping the state. Only for an idle host;
later registrations are left for `deinit`.

```zig
pub fn runCloseFinalizers(gc: *Gc) void
```

References: [`Gc`](#type-gc)

<a id="fn-tablecapacitybytes"></a>

## tableCapacityBytes

```zig
pub fn tableCapacityBytes(table: *const Table) usize
```

<a id="fn-tablegcbytes"></a>

## tableGcBytes

```zig
pub fn tableGcBytes(table: *const Table) usize
```

<a id="fn-userdatabytes"></a>

## userdataBytes

```zig
pub fn userdataBytes(userdata: *const Userdata) usize
```

