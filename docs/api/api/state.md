# api.state

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

- [gcBoundary](#fn-gcboundary)
- [appendMemoryFile](#fn-appendmemoryfile)
- [deinitOwnedMemoryFiles](#fn-deinitownedmemoryfiles)

## Types

- [InterruptHandle](#type-interrupthandle)
- [State](#type-state)

<a id="type-interrupthandle"></a>

## InterruptHandle

Copyable, thread-safe handle that stops Lua at the next safepoint with `error.Interrupted`.
Join threads using it before `State.deinit`. Lua cannot catch it and pending `__close`
handlers do not run. A request made while idle applies to the next execution.

```zig
pub const InterruptHandle = struct {
    control: *runtime.InterruptControl,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [interrupt](#fn-interrupthandle-interrupt) | `self: InterruptHandle` | `void` |  |
| [isPending](#fn-interrupthandle-ispending) | `self: InterruptHandle` | `bool` |  |

<a id="fn-interrupthandle-interrupt"></a>

### InterruptHandle.interrupt

```zig
pub fn interrupt(self: InterruptHandle) void
```

References: [`InterruptHandle`](#type-interrupthandle)

<a id="fn-interrupthandle-ispending"></a>

### InterruptHandle.isPending

```zig
pub fn isPending(self: InterruptHandle) bool
```

References: [`InterruptHandle`](#type-interrupthandle)

<a id="type-state"></a>

## State

Owns a Lua VM and its host-facing API state.

```zig
pub const State = struct {
    base_allocator: std.mem.Allocator,
    /// Advances on successful reset; handles from prior generations are invalid.
    generation: u64 = 0,
    /// Active snapshot baseline; null before capture.
    baseline: ?*const SnapshotBacking = null,
    /// Owner of borrowed bytecode; capture may replace the active baseline.
    immutable_owner: ?*const SnapshotBacking = null,
    rollback_metadata: ?RollbackMetadata = null,
    /// Stable allocator wrapper; unlimited until a memory limit is set.
    memory_limit_allocator: ?*MemoryLimitAllocator = null,
    raw_state: runtime.State,
    /// Registry root for the last captured Lua error value.
    last_error_root: ?usize = null,
    /// Traceback captured with the last error by `Function.callWith`.
    last_error_traceback: ?[]u8 = null,
    /// Owned entries visible to the memory filesystem.
    memory_files: std.ArrayList(MemoryFile) = .empty,
    /// Whether each memory-file entry owns its contents slice.
    memory_file_owned_contents: std.ArrayList(bool) = .empty,
    callbacks: std.ArrayList(RegisteredCallback) = .empty,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [init](#fn-state-init) | `state_allocator: std.mem.Allocator, options: Options` | `!State` | &#96;state_allocator&#96; must remain valid until &#96;deinit&#96;. |
| [deinit](#fn-state-deinit) | `self: *State` | `void` | Runs pending finalizers like &#96;lua_close&#96; (errors ignored, open files flushed), then frees the state and invalidates all handles. &#96;reset&#96; runs no finalizers. |
| [snapshot](#fn-state-snapshot) | `self: *State, snapshot_allocator: std.mem.Allocator` | `!Snapshot` | Captures an idle VM, including suspended coroutines, as the new reset baseline. Borrowed capabilities and &#96;snapshot_allocator&#96; must outlive every state retaining it. |
| [reset](#fn-state-reset) | `self: *State` | `!void` | Restores the active baseline and invalidates prior handles; &#96;error.NoSnapshot&#96; without one. Fails atomically. Skips Lua &#96;__gc&#96; and &#96;__close&#96; handlers and discards file handles opened since the baseline without flushing them. |
| [allocator](#fn-state-allocator) | `self: *State` | `std.mem.Allocator` | Allocator for API-owned allocations returned to the host. |
| [instructionBudget](#fn-state-instructionbudget) | `self: *const State` | `InstructionBudget` |  |
| [resetInstructionBudget](#fn-state-resetinstructionbudget) | `self: *State` | `void` |  |
| [interruptHandle](#fn-state-interrupthandle) | `self: *State` | `!InterruptHandle` | Returns a thread-safe &#96;InterruptHandle&#96;; handles share one flag that stays valid across &#96;reset&#96; until &#96;deinit&#96;. While one exists, dispatch polls the flag periodically. |
| [clearInterrupt](#fn-state-clearinterrupt) | `self: *State` | `void` |  |
| [isInterruptPending](#fn-state-isinterruptpending) | `self: *const State` | `bool` |  |
| [openLibs](#fn-state-openlibs) | `self: *State, selection: Stdlib` | `!void` |  |
| [collect](#fn-state-collect) | `self: *State` | `!void` | Runs a full collection and pending finalizers, even while automatic GC is stopped. |
| [stepGc](#fn-state-stepgc) | `self: *State, budget: GcBudget` | `!GcStepResult` | Runs at most &#96;budget.steps&#96; basic steps, even while stopped; bounds work, not time. |
| [gcMode](#fn-state-gcmode) | `self: *const State` | `GcMode` |  |
| [setGcMode](#fn-state-setgcmode) | `self: *State, mode: GcMode` | `GcMode` | Returns the previous mode. |
| [gcParam](#fn-state-gcparam) | `self: *const State, param: GcParam` | `i64` |  |
| [setGcParam](#fn-state-setgcparam) | `self: *State, param: GcParam, value: i64` | `!i64` | Returns the previous value; values outside 0...maxInt(i32) return &#96;error.InvalidGcParam&#96;. |
| [stopGc](#fn-state-stopgc) | `self: *State` | `void` |  |
| [restartGc](#fn-state-restartgc) | `self: *State` | `void` |  |
| [isGcRunning](#fn-state-isgcrunning) | `self: *const State` | `bool` |  |
| [push](#fn-state-push) | `self: *State, value: anytype` | `!Value` | Converts a Zig value into a rooted &#96;Value&#96;. |
| [read](#fn-state-read) | `self: *State, value: Value, comptime T: type` | `!T` | A &#96;[]const u8&#96; result borrows VM memory; see &#96;Value.string&#96;. |
| [setGlobal](#fn-state-setglobal) | `self: *State, name: []const u8, value: anytype` | `!void` |  |
| [getGlobal](#fn-state-getglobal) | `self: *State, name: []const u8, comptime T: type` | `!T` | A &#96;[]const u8&#96; result borrows VM memory; see &#96;Value.string&#96;. |
| [register](#fn-state-register) | `self: *State, name: []const u8, callback: HostFn` | `!Function` | Wraps an untyped callback as a Lua function; it is not installed automatically. |
| [registerTyped](#fn-state-registertyped) | `self: *State, name: []const u8, comptime function: anytype` | `!Function` | Like &#96;register&#96;, reading parameters from Lua arguments by type; &#96;*Context&#96; is injected. |
| [registerUserdataInitializerWith](#fn-state-registeruserdatainitializerwith) | `self: *State, comptime T: type, name: []const u8, comptime initializer: anytype, comptime options: UserdataOptions(T)` | `!Function` | Registers a Lua constructor that reads &#96;initializer&#96;'s arguments by type (&#96;*Context&#96; is injected) and wraps its &#96;T&#96; or &#96;!T&#96; result with &#96;newUserdataAuto&#96;. |
| [createTable](#fn-state-createtable) | `self: *State, options: TableOptions` | `!Table` |  |
| [newCoroutine](#fn-state-newcoroutine) | `self: *State, entry: Function` | `!Coroutine` | Creates a suspended coroutine; first resume arguments become &#96;entry&#96;'s arguments. |
| [newUserdata](#fn-state-newuserdata) | `self: *State, comptime T: type, value: T, options: UserdataOptions(T)` | `!Userdata(T)` | Allocates Lua-owned userdata initialized with &#96;value&#96;. |
| [newUserdataAuto](#fn-state-newuserdataauto) | `self: *State, comptime T: type, value: T, options: UserdataOptions(T)` | `!Userdata(T)` | Like &#96;newUserdata&#96;, also installing &#96;T&#96;'s methods whose receiver is &#96;*T&#96; or &#96;*const T&#96;; names starting with &#96;__&#96; become metamethods. |
| [newUserdataPtr](#fn-state-newuserdataptr) | `self: *State, comptime T: type, ptr: *T, options: UserdataPtrOptions(T)` | `!Userdata(T)` | Wraps host-owned &#96;ptr&#96; as userdata without taking ownership. |
| [newUserdataPtrAuto](#fn-state-newuserdataptrauto) | `self: *State, comptime T: type, ptr: *T, options: UserdataPtrOptions(T)` | `!Userdata(T)` | Like &#96;newUserdataPtr&#96;, also installing &#96;T&#96;'s methods as in &#96;newUserdataAuto&#96;. |
| [createModule](#fn-state-createmodule) | `self: *State, name: []const u8` | `!Table` | Creates a module table; it is not installed (see &#96;setLoadedModule&#96;). |
| [setLoadedModule](#fn-state-setloadedmodule) | `self: *State, name: []const u8, module: anytype` | `!void` | Sets &#96;package.loaded[name]&#96; so &#96;require(name)&#96; returns &#96;module&#96;; opens &#96;package&#96; if needed. |
| [preloadModule](#fn-state-preloadmodule) | `self: *State, name: []const u8, loader: Function` | `!void` | Sets &#96;package.preload[name]&#96;, opening &#96;package&#96; if needed. The host keeps its &#96;loader&#96; handle. |
| [preloadModuleFn](#fn-state-preloadmodulefn) | `self: *State, name: []const u8, comptime loader: anytype` | `!void` | Registers &#96;loader&#96; like &#96;registerTyped&#96; and installs it with &#96;preloadModule&#96;. |
| [require](#fn-state-require) | `self: *State, name: []const u8, comptime T: type` | `!T` | Calls the built-in &#96;require(name)&#96;, opening &#96;package&#96; if needed, and converts the result. Loaders cannot yield; use &#96;Tuple(&.{ M, []const u8 })&#96; to also read the loader data. |
| [setPackagePath](#fn-state-setpackagepath) | `self: *State, path: []const u8` | `!void` | Sets &#96;package.path&#96;, opening the package library if needed. |
| [addMemoryFile](#fn-state-addmemoryfile) | `self: *State, path: []const u8, contents: []const u8` | `!void` | Adds an owned copy to the memory filesystem, or writes through a writable one. Host and custom filesystems return &#96;error.UnsupportedOption&#96;. |
| [loadString](#fn-state-loadstring) | `self: *State, source: []const u8, options: LoadOptions` | `!Function` |  |
| [loadFile](#fn-state-loadfile) | `self: *State, path: []const u8, options: LoadOptions` | `!Function` | Loads through the configured filesystem capability. |
| [loadBytecode](#fn-state-loadbytecode) | `self: *State, bytecode: []const u8, options: BytecodeLoadOptions` | `!Function` |  |
| [doString](#fn-state-dostring) | `self: *State, source: []const u8, options: DoOptions` | `!void` |  |
| [doFile](#fn-state-dofile) | `self: *State, path: []const u8, options: DoOptions` | `!void` |  |
| [exitRequest](#fn-state-exitrequest) | `self: *const State` | `?ExitRequest` | Exit recorded by &#96;os.exit&#96; after &#96;error.LuaExit&#96;, or null. &#96;close&#96; means Lua asked to close the state; pending to-be-closed variables have already run. |
| [clearExitRequest](#fn-state-clearexitrequest) | `self: *State` | `void` |  |
| [setWarnings](#fn-state-setwarnings) | `self: *State, on: bool` | `void` |  |
| [errorMessage](#fn-state-errormessage) | `self: *State` | `![]const u8` | Formats the last Lua error; the caller frees the result with &#96;allocator()&#96;. |
| [takeErrorValue](#fn-state-takeerrorvalue) | `self: *State` | `?ErrorRef` | Takes ownership of the last Lua error value; the caller must &#96;deinit&#96; it. |

<a id="fn-state-init"></a>

### State.init

`state_allocator` must remain valid until `deinit`.

```zig
pub fn init(state_allocator: std.mem.Allocator, options: Options) !State
```

References: [`State`](#type-state)

<a id="fn-state-deinit"></a>

### State.deinit

Runs pending finalizers like `lua_close` (errors ignored, open files flushed), then
frees the state and invalidates all handles. `reset` runs no finalizers.

```zig
pub fn deinit(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-snapshot"></a>

### State.snapshot

Captures an idle VM, including suspended coroutines, as the new reset baseline.
Borrowed capabilities and `snapshot_allocator` must outlive every state retaining it.

```zig
pub fn snapshot(self: *State, snapshot_allocator: std.mem.Allocator) !Snapshot
```

References: [`State`](#type-state)

<a id="fn-state-reset"></a>

### State.reset

Restores the active baseline and invalidates prior handles; `error.NoSnapshot` without one.
Fails atomically. Skips Lua `__gc` and `__close` handlers and discards file handles
opened since the baseline without flushing them.

```zig
pub fn reset(self: *State) !void
```

References: [`State`](#type-state)

<a id="fn-state-allocator"></a>

### State.allocator

Allocator for API-owned allocations returned to the host.

```zig
pub fn allocator(self: *State) std.mem.Allocator
```

References: [`State`](#type-state)

<a id="fn-state-instructionbudget"></a>

### State.instructionBudget

```zig
pub fn instructionBudget(self: *const State) InstructionBudget
```

References: [`State`](#type-state)

<a id="fn-state-resetinstructionbudget"></a>

### State.resetInstructionBudget

```zig
pub fn resetInstructionBudget(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-interrupthandle"></a>

### State.interruptHandle

Returns a thread-safe `InterruptHandle`; handles share one flag that stays valid across
`reset` until `deinit`. While one exists, dispatch polls the flag periodically.

```zig
pub fn interruptHandle(self: *State) !InterruptHandle
```

References: [`State`](#type-state), [`InterruptHandle`](#type-interrupthandle)

<a id="fn-state-clearinterrupt"></a>

### State.clearInterrupt

```zig
pub fn clearInterrupt(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-isinterruptpending"></a>

### State.isInterruptPending

```zig
pub fn isInterruptPending(self: *const State) bool
```

References: [`State`](#type-state)

<a id="fn-state-openlibs"></a>

### State.openLibs

```zig
pub fn openLibs(self: *State, selection: Stdlib) !void
```

References: [`State`](#type-state)

<a id="fn-state-collect"></a>

### State.collect

Runs a full collection and pending finalizers, even while automatic GC is stopped.

```zig
pub fn collect(self: *State) !void
```

References: [`State`](#type-state)

<a id="fn-state-stepgc"></a>

### State.stepGc

Runs at most `budget.steps` basic steps, even while stopped; bounds work, not time.

```zig
pub fn stepGc(self: *State, budget: GcBudget) !GcStepResult
```

References: [`State`](#type-state)

<a id="fn-state-gcmode"></a>

### State.gcMode

```zig
pub fn gcMode(self: *const State) GcMode
```

References: [`State`](#type-state)

<a id="fn-state-setgcmode"></a>

### State.setGcMode

Returns the previous mode.

```zig
pub fn setGcMode(self: *State, mode: GcMode) GcMode
```

References: [`State`](#type-state)

<a id="fn-state-gcparam"></a>

### State.gcParam

```zig
pub fn gcParam(self: *const State, param: GcParam) i64
```

References: [`State`](#type-state)

<a id="fn-state-setgcparam"></a>

### State.setGcParam

Returns the previous value; values outside 0...maxInt(i32) return `error.InvalidGcParam`.

```zig
pub fn setGcParam(self: *State, param: GcParam, value: i64) !i64
```

References: [`State`](#type-state)

<a id="fn-state-stopgc"></a>

### State.stopGc

```zig
pub fn stopGc(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-restartgc"></a>

### State.restartGc

```zig
pub fn restartGc(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-isgcrunning"></a>

### State.isGcRunning

```zig
pub fn isGcRunning(self: *const State) bool
```

References: [`State`](#type-state)

<a id="fn-state-push"></a>

### State.push

Converts a Zig value into a rooted `Value`.

```zig
pub fn push(self: *State, value: anytype) !Value
```

References: [`State`](#type-state)

<a id="fn-state-read"></a>

### State.read

A `[]const u8` result borrows VM memory; see `Value.string`.

```zig
pub fn read(self: *State, value: Value, comptime T: type) !T
```

References: [`State`](#type-state)

<a id="fn-state-setglobal"></a>

### State.setGlobal

```zig
pub fn setGlobal(self: *State, name: []const u8, value: anytype) !void
```

References: [`State`](#type-state)

<a id="fn-state-getglobal"></a>

### State.getGlobal

A `[]const u8` result borrows VM memory; see `Value.string`.

```zig
pub fn getGlobal(self: *State, name: []const u8, comptime T: type) !T
```

References: [`State`](#type-state)

<a id="fn-state-register"></a>

### State.register

Wraps an untyped callback as a Lua function; it is not installed automatically.

```zig
pub fn register(self: *State, name: []const u8, callback: HostFn) !Function
```

References: [`State`](#type-state)

<a id="fn-state-registertyped"></a>

### State.registerTyped

Like `register`, reading parameters from Lua arguments by type; `*Context` is injected.

```zig
pub fn registerTyped(self: *State, name: []const u8, comptime function: anytype) !Function
```

References: [`State`](#type-state)

<a id="fn-state-registeruserdatainitializerwith"></a>

### State.registerUserdataInitializerWith

Registers a Lua constructor that reads `initializer`'s arguments by type (`*Context` is
injected) and wraps its `T` or `!T` result with `newUserdataAuto`.

```zig
pub fn registerUserdataInitializerWith(self: *State, comptime T: type, name: []const u8, comptime initializer: anytype, comptime options: UserdataOptions(T)) !Function
```

References: [`State`](#type-state)

<a id="fn-state-createtable"></a>

### State.createTable

```zig
pub fn createTable(self: *State, options: TableOptions) !Table
```

References: [`State`](#type-state)

<a id="fn-state-newcoroutine"></a>

### State.newCoroutine

Creates a suspended coroutine; first resume arguments become `entry`'s arguments.

```zig
pub fn newCoroutine(self: *State, entry: Function) !Coroutine
```

References: [`State`](#type-state)

<a id="fn-state-newuserdata"></a>

### State.newUserdata

Allocates Lua-owned userdata initialized with `value`.

```zig
pub fn newUserdata(self: *State, comptime T: type, value: T, options: UserdataOptions(T)) !Userdata(T)
```

References: [`State`](#type-state)

<a id="fn-state-newuserdataauto"></a>

### State.newUserdataAuto

Like `newUserdata`, also installing `T`'s methods whose receiver is `*T` or `*const T`;
names starting with `__` become metamethods.

```zig
pub fn newUserdataAuto(self: *State, comptime T: type, value: T, options: UserdataOptions(T)) !Userdata(T)
```

References: [`State`](#type-state)

<a id="fn-state-newuserdataptr"></a>

### State.newUserdataPtr

Wraps host-owned `ptr` as userdata without taking ownership.

```zig
pub fn newUserdataPtr(self: *State, comptime T: type, ptr: *T, options: UserdataPtrOptions(T)) !Userdata(T)
```

References: [`State`](#type-state)

<a id="fn-state-newuserdataptrauto"></a>

### State.newUserdataPtrAuto

Like `newUserdataPtr`, also installing `T`'s methods as in `newUserdataAuto`.

```zig
pub fn newUserdataPtrAuto(self: *State, comptime T: type, ptr: *T, options: UserdataPtrOptions(T)) !Userdata(T)
```

References: [`State`](#type-state)

<a id="fn-state-createmodule"></a>

### State.createModule

Creates a module table; it is not installed (see `setLoadedModule`).

```zig
pub fn createModule(self: *State, name: []const u8) !Table
```

References: [`State`](#type-state)

<a id="fn-state-setloadedmodule"></a>

### State.setLoadedModule

Sets `package.loaded[name]` so `require(name)` returns `module`; opens `package` if needed.

```zig
pub fn setLoadedModule(self: *State, name: []const u8, module: anytype) !void
```

References: [`State`](#type-state)

<a id="fn-state-preloadmodule"></a>

### State.preloadModule

Sets `package.preload[name]`, opening `package` if needed. The host keeps its `loader` handle.

```zig
pub fn preloadModule(self: *State, name: []const u8, loader: Function) !void
```

References: [`State`](#type-state)

<a id="fn-state-preloadmodulefn"></a>

### State.preloadModuleFn

Registers `loader` like `registerTyped` and installs it with `preloadModule`.

```zig
pub fn preloadModuleFn(self: *State, name: []const u8, comptime loader: anytype) !void
```

References: [`State`](#type-state)

<a id="fn-state-require"></a>

### State.require

Calls the built-in `require(name)`, opening `package` if needed, and converts the result.
Loaders cannot yield; use `Tuple(&.{ M, []const u8 })` to also read the loader data.

```zig
pub fn require(self: *State, name: []const u8, comptime T: type) !T
```

References: [`State`](#type-state)

<a id="fn-state-setpackagepath"></a>

### State.setPackagePath

Sets `package.path`, opening the package library if needed.

```zig
pub fn setPackagePath(self: *State, path: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-addmemoryfile"></a>

### State.addMemoryFile

Adds an owned copy to the memory filesystem, or writes through a writable one.
Host and custom filesystems return `error.UnsupportedOption`.

```zig
pub fn addMemoryFile(self: *State, path: []const u8, contents: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-loadstring"></a>

### State.loadString

```zig
pub fn loadString(self: *State, source: []const u8, options: LoadOptions) !Function
```

References: [`State`](#type-state)

<a id="fn-state-loadfile"></a>

### State.loadFile

Loads through the configured filesystem capability.

```zig
pub fn loadFile(self: *State, path: []const u8, options: LoadOptions) !Function
```

References: [`State`](#type-state)

<a id="fn-state-loadbytecode"></a>

### State.loadBytecode

```zig
pub fn loadBytecode(self: *State, bytecode: []const u8, options: BytecodeLoadOptions) !Function
```

References: [`State`](#type-state)

<a id="fn-state-dostring"></a>

### State.doString

```zig
pub fn doString(self: *State, source: []const u8, options: DoOptions) !void
```

References: [`State`](#type-state)

<a id="fn-state-dofile"></a>

### State.doFile

```zig
pub fn doFile(self: *State, path: []const u8, options: DoOptions) !void
```

References: [`State`](#type-state)

<a id="fn-state-exitrequest"></a>

### State.exitRequest

Exit recorded by `os.exit` after `error.LuaExit`, or null. `close` means Lua asked to
close the state; pending to-be-closed variables have already run.

```zig
pub fn exitRequest(self: *const State) ?ExitRequest
```

References: [`State`](#type-state)

<a id="fn-state-clearexitrequest"></a>

### State.clearExitRequest

```zig
pub fn clearExitRequest(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-setwarnings"></a>

### State.setWarnings

```zig
pub fn setWarnings(self: *State, on: bool) void
```

References: [`State`](#type-state)

<a id="fn-state-errormessage"></a>

### State.errorMessage

Formats the last Lua error; the caller frees the result with `allocator()`.

```zig
pub fn errorMessage(self: *State) ![]const u8
```

References: [`State`](#type-state)

<a id="fn-state-takeerrorvalue"></a>

### State.takeErrorValue

Takes ownership of the last Lua error value; the caller must `deinit` it.

```zig
pub fn takeErrorValue(self: *State) ?ErrorRef
```

References: [`State`](#type-state)

<a id="fn-gcboundary"></a>

## gcBoundary

```zig
pub fn gcBoundary(state: *State) !void
```

References: [`State`](#type-state)

<a id="fn-appendmemoryfile"></a>

## appendMemoryFile

```zig
pub fn appendMemoryFile(state: *State, path: []const u8, contents: []const u8, owned_contents: bool) !void
```

References: [`State`](#type-state)

<a id="fn-deinitownedmemoryfiles"></a>

## deinitOwnedMemoryFiles

```zig
pub fn deinitOwnedMemoryFiles(state: *State, state_allocator: std.mem.Allocator) void
```

References: [`State`](#type-state)

