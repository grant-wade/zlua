# api

## Navigation

- [API Index](README.md)

<details>
<summary>All documents</summary>

- [root](root.md)
- [frontend](frontend.md)
- [errors](errors.md)
- [frontend.source](frontend/source.md)
- [frontend.token](frontend/token.md)
- [frontend.diagnostic](frontend/diagnostic.md)
- [frontend.lexer](frontend/lexer.md)
- [frontend.ast](frontend/ast.md)
- [frontend.parser](frontend/parser.md)
- [compile](compile.md)
- [compile.resolver](compile/resolver.md)
- [compile.bytecode](compile/bytecode.md)
- [compile.proto](compile/proto.md)
- [runtime.types](runtime/types.md)
- [runtime](runtime.md)
- [runtime.chunk](runtime/chunk.md)
- [reflection](reflection.md)
- [runtime.value](runtime/value.md)
- [runtime.number_format](runtime/number_format.md)
- [runtime.execute](runtime/execute.md)
- [testing.process](testing/process.md)
- [runtime.state](runtime/state.md)
- [runtime.rollback](runtime/rollback.md)
- [runtime.call](runtime/call.md)
- [runtime.coroutine](runtime/coroutine.md)
- [runtime.debug](runtime/debug.md)
- [runtime.gc](runtime/gc.md)
- [runtime.host](runtime/host.md)
- [runtime.timezone](runtime/timezone.md)
- [stdlib](stdlib.md)
- [stdlib.base](stdlib/base.md)
- [stdlib.table](stdlib/table.md)
- [stdlib.string](stdlib/string.md)
- [stdlib.math](stdlib/math.md)
- [stdlib.utf8](stdlib/utf8.md)
- [stdlib.coroutine](stdlib/coroutine.md)
- [stdlib.debug](stdlib/debug.md)
- [stdlib.io](stdlib/io.md)
- [stdlib.static_strings](stdlib/static_strings.md)
- [stdlib.os](stdlib/os.md)
- [stdlib.package](stdlib/package.md)
- [stdlib.json](stdlib/json.md)
- [stdlib.zerde_lua](stdlib/zerde_lua.md)
- [stdlib.toml](stdlib/toml.md)
- [stdlib.msgpack](stdlib/msgpack.md)
- [stdlib.csv](stdlib/csv.md)
- [stdlib.fs](stdlib/fs.md)
- [runtime.vm](runtime/vm.md)
- [runtime.tests](runtime/tests.md)
- [runtime.internal](runtime/internal.md)
- [compile.compiler](compile/compiler.md)
- [compile.fold](compile/fold.md)
- [compile.disasm](compile/disasm.md)
- [api](api.md)
- [runtime.snapshot](runtime/snapshot.md)
- [testing](testing.md)
- [testing.clua](testing/clua.md)
- [testing.bench_runner](testing/bench_runner.md)
- [testing.bench.options](testing/bench/options.md)
- [testing.bench.results](testing/bench/results.md)
- [testing.bench.stats](testing/bench/stats.md)
- [testing.bench.report](testing/bench/report.md)
- [testing.bench.process](testing/bench/process.md)
- [testing.bench.fixtures](testing/bench/fixtures.md)
- [testing.bench.legacy_process](testing/bench/legacy_process.md)
- [testing.bench.startup](testing/bench/startup.md)
- [testing.bench.allocation](testing/bench/allocation.md)
- [testing.bench.c_startup](testing/bench/c_startup.md)
- [testing.bench.snapshots](testing/bench/snapshots.md)
- [testing.bench.gc](testing/bench/gc.md)
- [testing.diff_runner](testing/diff_runner.md)
- [testing.fixtures](testing/fixtures.md)
- [testing.expected_failures](testing/expected_failures.md)
- [testing.metadata](testing/metadata.md)
- [testing.normalizer](testing/normalizer.md)
- [testing.extension_runner](testing/extension_runner.md)
- [testing.official_suite](testing/official_suite.md)

</details>

## Overview

Zig-native embedding API for zlua: a Lua 5.5 state driven with Zig values,
explicit host capabilities, rooted handles, and Zig errors.

Rooted handles (`Table`, `Function`, `Coroutine`, `Ref`, `Userdata(T)`, `AnyUserdata`,
`ErrorRef`, and `Value`s holding them) must be released with `deinit`. `State.reset`
invalidates prior handles and borrowed VM slices. The `runtime` module is internal.
See `docs/embedding.md` for capabilities, error handling, snapshots, and ownership.

## Functions

- [UserdataOptions](#fn-userdataoptions)
- [UserdataPtrOptions](#fn-userdataptroptions)
- [UserdataSnapshotHooks](#fn-userdatasnapshothooks)
- [Userdata](#fn-userdata)
- [CallResult](#fn-callresult)
- [Tuple](#fn-tuple)
- [ResumeResult](#fn-resumeresult)

## Types

- [Error](#type-error)
- [UnsupportedOption](#type-unsupportedoption)
- [ConversionError](#type-conversionerror)
- [Stdlib](#type-stdlib)
- [IoCapability](#type-iocapability)
- [Capabilities](#type-capabilities)
- [Limits](#type-limits)
- [CallOptions](#type-calloptions)
- [InterruptHandle](#type-interrupthandle)
- [InstructionBudget](#type-instructionbudget)
- [GcOptions](#type-gcoptions)
- [DebugOptions](#type-debugoptions)
- [Options](#type-options)
- [LoadMode](#type-loadmode)
- [LoadOptions](#type-loadoptions)
- [BytecodeLoadOptions](#type-bytecodeloadoptions)
- [BytecodeDumpOptions](#type-bytecodedumpoptions)
- [TableOptions](#type-tableoptions)
- [GcBudget](#type-gcbudget)
- [GcStepResult](#type-gcstepresult)
- [State](#type-state)
- [Snapshot](#type-snapshot)
- [Ref](#type-ref)
- [Table](#type-table)
- [Function](#type-function)
- [AnyUserdata](#type-anyuserdata)
- [ErrorRef](#type-errorref)
- [Value](#type-value)
- [Context](#type-context)
- [Coroutine](#type-coroutine)

## Constants

- [HostFn](#const-hostfn)

## Aliases

- [LibrarySet](#alias-libraryset)
- [MemoryFile](#alias-memoryfile)
- [MemoryFilesystem](#alias-memoryfilesystem)
- [OutputFlush](#alias-outputflush)
- [FilesystemCapability](#alias-filesystemcapability)
- [CustomFilesystem](#alias-customfilesystem)
- [HostDirectory](#alias-hostdirectory)
- [FilesystemFileKind](#alias-filesystemfilekind)
- [FilesystemFileStat](#alias-filesystemfilestat)
- [FilesystemDirectoryEntry](#alias-filesystemdirectoryentry)
- [deinitFilesystemDirectoryEntries](#alias-deinitfilesystemdirectoryentries)
- [EnvironmentCapability](#alias-environmentcapability)
- [CustomEnvironment](#alias-customenvironment)
- [ClockCapability](#alias-clockcapability)
- [CustomClock](#alias-customclock)
- [FixedClock](#alias-fixedclock)
- [UtcOffset](#alias-utcoffset)
- [ProcessCapability](#alias-processcapability)
- [CustomProcess](#alias-customprocess)
- [ProcessResult](#alias-processresult)
- [ProcessStatus](#alias-processstatus)
- [PopenResult](#alias-popenresult)
- [ExitRequest](#alias-exitrequest)
- [WarningHandler](#alias-warninghandler)
- [GcMode](#alias-gcmode)
- [GcParam](#alias-gcparam)
- [GcParams](#alias-gcparams)
- [DoOptions](#alias-dooptions)
- [CoroutineStatus](#alias-coroutinestatus)

<a id="type-error"></a>

## Error

`LuaError`: Lua syntax/runtime error. `LuaExit`: `os.exit` ran; see `State.exitRequest`.
`Interrupted`: stopped by an `InterruptHandle`. Lua cannot catch exits or interrupts.

```zig
pub const Error = error{
    LuaError,
    LuaExit,
    Interrupted,
};
```

<a id="type-unsupportedoption"></a>

## UnsupportedOption

```zig
pub const UnsupportedOption = error{
    UnsupportedOption,
};
```

<a id="type-conversionerror"></a>

## ConversionError

```zig
pub const ConversionError = error{
    TypeMismatch,
    IntegerOutOfRange,
    UnsupportedType,
    ArityMismatch,
};
```

<a id="fn-userdataoptions"></a>

## UserdataOptions

```zig
pub fn UserdataOptions(comptime T: type) type
```

<a id="fn-userdataptroptions"></a>

## UserdataPtrOptions

```zig
pub fn UserdataPtrOptions(comptime T: type) type
```

<a id="fn-userdatasnapshothooks"></a>

## UserdataSnapshotHooks

[Snapshot](#type-snapshot) copy/dispose hooks for userdata payloads. Copies must own all nested storage and
must not retain VM pointers or reenter snapshot operations. Hooks must be thread-safe:
concurrent `Snapshot.newState` calls may copy one payload, and disposal runs on any thread.

```zig
pub fn UserdataSnapshotHooks(comptime T: type) type
```

<a id="alias-libraryset"></a>

## LibrarySet

```zig
pub const LibrarySet = stdlib.LibrarySet;
```

References: [`stdlib.LibrarySet`](stdlib.md#type-libraryset)

<a id="type-stdlib"></a>

## Stdlib

```zig
pub const Stdlib = union(enum) {
    none,
    base,
    /// Libraries safe for sandboxed embedding.
    safe,
    /// All libraries; host capabilities still gate ambient access.
    full,
    custom: LibrarySet,
};
```

<a id="alias-memoryfile"></a>

## MemoryFile

```zig
pub const MemoryFile = runtime.MemoryFile;
```

References: [`runtime.MemoryFile`](runtime.md#alias-memoryfile)

<a id="alias-memoryfilesystem"></a>

## MemoryFilesystem

Writable in-memory filesystem.

```zig
pub const MemoryFilesystem = runtime.MemoryFilesystem;
```

References: [`runtime.MemoryFilesystem`](runtime.md#alias-memoryfilesystem)

<a id="alias-outputflush"></a>

## OutputFlush

When Lua output writers are flushed beyond explicit flush points.

```zig
pub const OutputFlush = runtime.OutputFlush;
```

References: [`runtime.OutputFlush`](runtime.md#alias-outputflush)

<a id="type-iocapability"></a>

## IoCapability

```zig
pub const IoCapability = struct {
    /// Required by host-backed filesystem, clock, and process operations.
    runtime: ?std.Io = null,
    /// Bytes returned by Lua stdin reads.
    stdin: []const u8 = "",
    /// Receives `print` and `io.write` output.
    stdout: ?*std.Io.Writer = null,
    stderr: ?*std.Io.Writer = null,
    /// Flush policy beyond `io.flush`, `os.exit`, and child process starts.
    stdout_flush: OutputFlush = .explicit,
    stderr_flush: OutputFlush = .explicit,
    /// Start with warnings on, like `lua -W`.
    warnings: bool = false,
    /// Receives complete warnings instead of `stderr`; must not call back into the state.
    warning_handler: ?WarningHandler = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [disabled](#const-iocapability-disabled) |  |  |  |

<a id="const-iocapability-disabled"></a>

### IoCapability.disabled

```zig
pub const disabled: IoCapability = .{};
```

References: [`IoCapability`](#type-iocapability)

<a id="alias-filesystemcapability"></a>

## FilesystemCapability

Filesystem access granted to Lua file APIs, `loadfile`, `dofile`, and `require`.

```zig
pub const FilesystemCapability = runtime.FilesystemCapability;
```

References: [`runtime.FilesystemCapability`](runtime.md#alias-filesystemcapability)

<a id="alias-customfilesystem"></a>

## CustomFilesystem

```zig
pub const CustomFilesystem = runtime.CustomFilesystem;
```

References: [`runtime.CustomFilesystem`](runtime.md#alias-customfilesystem)

<a id="alias-hostdirectory"></a>

## HostDirectory

Borrowed directory root that scopes host filesystem access.

```zig
pub const HostDirectory = runtime.HostDirectory;
```

References: [`runtime.HostDirectory`](runtime.md#alias-hostdirectory)

<a id="alias-filesystemfilekind"></a>

## FilesystemFileKind

```zig
pub const FilesystemFileKind = runtime.FilesystemFileKind;
```

References: [`runtime.FilesystemFileKind`](runtime.md#alias-filesystemfilekind)

<a id="alias-filesystemfilestat"></a>

## FilesystemFileStat

```zig
pub const FilesystemFileStat = runtime.FilesystemFileStat;
```

References: [`runtime.FilesystemFileStat`](runtime.md#alias-filesystemfilestat)

<a id="alias-filesystemdirectoryentry"></a>

## FilesystemDirectoryEntry

```zig
pub const FilesystemDirectoryEntry = runtime.FilesystemDirectoryEntry;
```

References: [`runtime.FilesystemDirectoryEntry`](runtime.md#alias-filesystemdirectoryentry)

<a id="alias-deinitfilesystemdirectoryentries"></a>

## deinitFilesystemDirectoryEntries

```zig
pub const deinitFilesystemDirectoryEntries = runtime.deinitFilesystemDirectoryEntries;
```

References: [`runtime.deinitFilesystemDirectoryEntries`](runtime.md#alias-deinitfilesystemdirectoryentries)

<a id="alias-environmentcapability"></a>

## EnvironmentCapability

Environment-variable access granted to `os.getenv` and enabled child processes.

```zig
pub const EnvironmentCapability = runtime.EnvironmentCapability;
```

References: [`runtime.EnvironmentCapability`](runtime.md#alias-environmentcapability)

<a id="alias-customenvironment"></a>

## CustomEnvironment

```zig
pub const CustomEnvironment = runtime.CustomEnvironment;
```

References: [`runtime.CustomEnvironment`](runtime.md#alias-customenvironment)

<a id="alias-clockcapability"></a>

## ClockCapability

Clock access granted to `os.time`, `os.date`, and `os.clock`.

```zig
pub const ClockCapability = runtime.ClockCapability;
```

References: [`runtime.ClockCapability`](runtime.md#alias-clockcapability)

<a id="alias-customclock"></a>

## CustomClock

```zig
pub const CustomClock = runtime.CustomClock;
```

References: [`runtime.CustomClock`](runtime.md#alias-customclock)

<a id="alias-fixedclock"></a>

## FixedClock

```zig
pub const FixedClock = runtime.FixedClock;
```

References: [`runtime.FixedClock`](runtime.md#alias-fixedclock)

<a id="alias-utcoffset"></a>

## UtcOffset

```zig
pub const UtcOffset = runtime.UtcOffset;
```

References: [`runtime.UtcOffset`](runtime.md#alias-utcoffset)

<a id="alias-processcapability"></a>

## ProcessCapability

Process access granted to `os.execute`, `io.popen`, and `os.exit`.

```zig
pub const ProcessCapability = runtime.ProcessCapability;
```

References: [`runtime.ProcessCapability`](runtime.md#alias-processcapability)

<a id="alias-customprocess"></a>

## CustomProcess

```zig
pub const CustomProcess = runtime.CustomProcess;
```

References: [`runtime.CustomProcess`](runtime.md#alias-customprocess)

<a id="alias-processresult"></a>

## ProcessResult

```zig
pub const ProcessResult = runtime.ProcessResult;
```

References: [`runtime.ProcessResult`](runtime.md#alias-processresult)

<a id="alias-processstatus"></a>

## ProcessStatus

```zig
pub const ProcessStatus = runtime.ProcessStatus;
```

References: [`runtime.ProcessStatus`](runtime.md#alias-processstatus)

<a id="alias-popenresult"></a>

## PopenResult

```zig
pub const PopenResult = runtime.PopenResult;
```

References: [`runtime.PopenResult`](runtime.md#alias-popenresult)

<a id="alias-exitrequest"></a>

## ExitRequest

Exit code and close flag recorded by `os.exit`; see `State.exitRequest`.

```zig
pub const ExitRequest = runtime.ExitRequest;
```

References: [`runtime.ExitRequest`](runtime.md#alias-exitrequest)

<a id="alias-warninghandler"></a>

## WarningHandler

```zig
pub const WarningHandler = runtime.WarningHandler;
```

References: [`runtime.WarningHandler`](runtime.md#alias-warninghandler)

<a id="type-capabilities"></a>

## Capabilities

Host services available to opened standard libraries; all denied by default.

```zig
pub const Capabilities = struct {
    io: IoCapability = .disabled,
    filesystem: FilesystemCapability = .disabled,
    environment: EnvironmentCapability = .disabled,
    clock: ClockCapability = .disabled,
    process: ProcessCapability = .disabled,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [sandboxed](#const-capabilities-sandboxed) |  |  |  |

<a id="const-capabilities-sandboxed"></a>

### Capabilities.sandboxed

```zig
pub const sandboxed: Capabilities = .{};
```

References: [`Capabilities`](#type-capabilities)

<a id="type-limits"></a>

## Limits

```zig
pub const Limits = struct {
    /// Bytes allocated through the state's runtime allocator; null is unlimited.
    max_memory: ?usize = null,
    /// Null uses the runtime default.
    max_stack_values: ?usize = null,
    /// Null uses the runtime default.
    max_call_frames: ?usize = null,
    /// Instructions since the last budget reset; null is unlimited.
    max_instructions: ?u64 = null,
    /// Largest single file read by `io`, `loadfile`, `dofile`, `require`, `fs`, and `loadFile`.
    /// Reads also count against `max_memory`.
    max_file_bytes: usize = runtime.default_max_file_bytes,
};
```

<a id="type-calloptions"></a>

## CallOptions

[Options](#type-options) for `Function.callWith` and `Function.protectedCallWith`.

```zig
pub const CallOptions = struct {
    /// Per-call instruction budget covering nested calls and coroutines; nested budgets keep
    /// the tighter limit, and `Limits.max_instructions` still applies.
    max_instructions: ?u64 = null,
    /// Capture a traceback before failing frames unwind; read it via `ErrorRef.traceback`.
    traceback: bool = false,
    /// `xpcall`-style handler run at the error point before `__close` handlers; its first
    /// result becomes the error value. Must belong to the called state.
    message_handler: ?Function = null,
};
```

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

<a id="type-instructionbudget"></a>

## InstructionBudget

```zig
pub const InstructionBudget = struct {
    limit: ?u64,
    /// Instructions since state creation or the last reset.
    used: u64,
    remaining: ?u64,
};
```

<a id="alias-gcmode"></a>

## GcMode

```zig
pub const GcMode = runtime_types.GcMode;
```

<a id="alias-gcparam"></a>

## GcParam

```zig
pub const GcParam = runtime_types.GcParam;
```

<a id="alias-gcparams"></a>

## GcParams

Percentages, except stepsize, which is measured in bytes.

```zig
pub const GcParams = runtime_types.GcParams;
```

<a id="type-gcoptions"></a>

## GcOptions

```zig
pub const GcOptions = struct {
    mode: GcMode = .generational,
    running: bool = true,
    params: GcParams = .{},
};
```

<a id="type-debugoptions"></a>

## DebugOptions

```zig
pub const DebugOptions = struct {
    /// Richer internal error diagnostics.
    errors: bool = false,
    trace_vm: bool = false,
};
```

<a id="type-options"></a>

## Options

```zig
pub const Options = struct {
    stdlib: Stdlib = .safe,
    capabilities: Capabilities = .sandboxed,
    limits: Limits = .{},
    gc: GcOptions = .{},
    debug: DebugOptions = .{},
};
```

<a id="type-loadmode"></a>

## LoadMode

```zig
pub const LoadMode = enum {
    source_only,
    binary_only,
    source_or_binary,
};
```

<a id="type-loadoptions"></a>

## LoadOptions

```zig
pub const LoadOptions = struct {
    /// Chunk name for diagnostics, Lua-style `=name` or `@path`.
    name: ?[]const u8 = null,
    /// Table used as the chunk's `_ENV`.
    environment: ?Table = null,
    mode: LoadMode = .source_only,
};
```

<a id="alias-dooptions"></a>

## DoOptions

```zig
pub const DoOptions = LoadOptions;
```

References: [`LoadOptions`](#type-loadoptions)

<a id="type-bytecodeloadoptions"></a>

## BytecodeLoadOptions

```zig
pub const BytecodeLoadOptions = struct {
    /// Table used as the loaded function's `_ENV`.
    environment: ?Table = null,
};
```

<a id="type-bytecodedumpoptions"></a>

## BytecodeDumpOptions

```zig
pub const BytecodeDumpOptions = struct {
    strip_debug: bool = false,
};
```

<a id="type-tableoptions"></a>

## TableOptions

```zig
pub const TableOptions = struct {
    array_hint: u32 = 0,
    hash_hint: u32 = 0,
};
```

<a id="const-hostfn"></a>

## HostFn

Untyped callback for `State.register`.

```zig
pub const HostFn = *const fn (ctx: *Context) anyerror!void;
```

References: [`Context`](#type-context)

<a id="type-gcbudget"></a>

## GcBudget

```zig
pub const GcBudget = struct {
    /// Maximum basic steps; zero requests one.
    steps: usize = 0,
};
```

<a id="type-gcstepresult"></a>

## GcStepResult

```zig
pub const GcStepResult = enum {
    /// A major cycle (incremental or generational) completed.
    complete,
    /// No major cycle completed, even if a minor collection ran.
    pending,
};
```

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

References: [`Options`](#type-options), [`State`](#type-state)

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

References: [`State`](#type-state), [`Snapshot`](#type-snapshot)

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

References: [`State`](#type-state), [`InstructionBudget`](#type-instructionbudget)

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

References: [`State`](#type-state), [`Stdlib`](#type-stdlib)

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

References: [`State`](#type-state), [`GcBudget`](#type-gcbudget), [`GcStepResult`](#type-gcstepresult)

<a id="fn-state-gcmode"></a>

### State.gcMode

```zig
pub fn gcMode(self: *const State) GcMode
```

References: [`State`](#type-state), [`GcMode`](#alias-gcmode)

<a id="fn-state-setgcmode"></a>

### State.setGcMode

Returns the previous mode.

```zig
pub fn setGcMode(self: *State, mode: GcMode) GcMode
```

References: [`State`](#type-state), [`GcMode`](#alias-gcmode)

<a id="fn-state-gcparam"></a>

### State.gcParam

```zig
pub fn gcParam(self: *const State, param: GcParam) i64
```

References: [`State`](#type-state), [`GcParam`](#alias-gcparam)

<a id="fn-state-setgcparam"></a>

### State.setGcParam

Returns the previous value; values outside 0...maxInt(i32) return `error.InvalidGcParam`.

```zig
pub fn setGcParam(self: *State, param: GcParam, value: i64) !i64
```

References: [`State`](#type-state), [`GcParam`](#alias-gcparam)

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

References: [`State`](#type-state), [`Value`](#type-value)

<a id="fn-state-read"></a>

### State.read

A `[]const u8` result borrows VM memory; see `Value.string`.

```zig
pub fn read(self: *State, value: Value, comptime T: type) !T
```

References: [`State`](#type-state), [`Value`](#type-value)

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

References: [`State`](#type-state), [`HostFn`](#const-hostfn), [`Function`](#type-function)

<a id="fn-state-registertyped"></a>

### State.registerTyped

Like `register`, reading parameters from Lua arguments by type; `*Context` is injected.

```zig
pub fn registerTyped(self: *State, name: []const u8, comptime function: anytype) !Function
```

References: [`State`](#type-state), [`Function`](#type-function)

<a id="fn-state-registeruserdatainitializerwith"></a>

### State.registerUserdataInitializerWith

Registers a Lua constructor that reads `initializer`'s arguments by type (`*Context` is
injected) and wraps its `T` or `!T` result with `newUserdataAuto`.

```zig
pub fn registerUserdataInitializerWith(self: *State, comptime T: type, name: []const u8, comptime initializer: anytype, comptime options: UserdataOptions(T)) !Function
```

References: [`State`](#type-state), [`Function`](#type-function)

<a id="fn-state-createtable"></a>

### State.createTable

```zig
pub fn createTable(self: *State, options: TableOptions) !Table
```

References: [`State`](#type-state), [`TableOptions`](#type-tableoptions), [`Table`](#type-table)

<a id="fn-state-newcoroutine"></a>

### State.newCoroutine

Creates a suspended coroutine; first resume arguments become `entry`'s arguments.

```zig
pub fn newCoroutine(self: *State, entry: Function) !Coroutine
```

References: [`State`](#type-state), [`Function`](#type-function), [`Coroutine`](#type-coroutine)

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

References: [`State`](#type-state), [`Table`](#type-table)

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

References: [`State`](#type-state), [`Function`](#type-function)

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

References: [`State`](#type-state), [`LoadOptions`](#type-loadoptions), [`Function`](#type-function)

<a id="fn-state-loadfile"></a>

### State.loadFile

Loads through the configured filesystem capability.

```zig
pub fn loadFile(self: *State, path: []const u8, options: LoadOptions) !Function
```

References: [`State`](#type-state), [`LoadOptions`](#type-loadoptions), [`Function`](#type-function)

<a id="fn-state-loadbytecode"></a>

### State.loadBytecode

```zig
pub fn loadBytecode(self: *State, bytecode: []const u8, options: BytecodeLoadOptions) !Function
```

References: [`State`](#type-state), [`BytecodeLoadOptions`](#type-bytecodeloadoptions), [`Function`](#type-function)

<a id="fn-state-dostring"></a>

### State.doString

```zig
pub fn doString(self: *State, source: []const u8, options: DoOptions) !void
```

References: [`State`](#type-state), [`DoOptions`](#alias-dooptions)

<a id="fn-state-dofile"></a>

### State.doFile

```zig
pub fn doFile(self: *State, path: []const u8, options: DoOptions) !void
```

References: [`State`](#type-state), [`DoOptions`](#alias-dooptions)

<a id="fn-state-exitrequest"></a>

### State.exitRequest

Exit recorded by `os.exit` after `error.LuaExit`, or null. `close` means Lua asked to
close the state; pending to-be-closed variables have already run.

```zig
pub fn exitRequest(self: *const State) ?ExitRequest
```

References: [`State`](#type-state), [`ExitRequest`](#alias-exitrequest)

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

References: [`State`](#type-state), [`ErrorRef`](#type-errorref)

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

Creates an independent [State](#type-state) with this snapshot as its baseline; it keeps the snapshot alive.

```zig
pub fn newState(self: *const Snapshot, state_allocator: std.mem.Allocator) !State
```

References: [`Snapshot`](#type-snapshot), [`State`](#type-state)

<a id="type-ref"></a>

## Ref

Rooted handle to any Lua value; unlike `Value.string`, keeps string bytes alive.

```zig
pub const Ref = struct {
    state: *State,
    index: usize,
    generation: u64,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-ref-deinit) | `self: *Ref` | `void` |  |
| [value](#fn-ref-value) | `self: Ref` | `!Value` |  |

<a id="fn-ref-deinit"></a>

### Ref.deinit

```zig
pub fn deinit(self: *Ref) void
```

References: [`Ref`](#type-ref)

<a id="fn-ref-value"></a>

### Ref.value

```zig
pub fn value(self: Ref) !Value
```

References: [`Ref`](#type-ref), [`Value`](#type-value)

<a id="type-table"></a>

## Table

Rooted handle to a Lua table.

```zig
pub const Table = struct {
    ref: Ref,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-table-deinit) | `self: *Table` | `void` |  |
| [get](#fn-table-get) | `self: Table, key: anytype, comptime T: type` | `!T` | Reads &#96;t[key]&#96; honoring &#96;__index&#96;; metamethods cannot yield and fail with &#96;error.LuaError&#96;. A &#96;[]const u8&#96; result borrows VM memory; see &#96;Value.string&#96;. |
| [set](#fn-table-set) | `self: Table, key: anytype, value: anytype` | `!void` | Assigns &#96;t[key]&#96; honoring &#96;__newindex&#96;; metamethods cannot yield. A nil or NaN key returns &#96;error.LuaError&#96;. |
| [rawSet](#fn-table-rawset) | `self: Table, key: anytype, value: anytype` | `!void` | Like &#96;set&#96; without &#96;__newindex&#96;; a nil or NaN key returns &#96;error.LuaError&#96;. |
| [append](#fn-table-append) | `self: Table, value: anytype` | `!void` | Raw-appends at &#96;rawLen() + 1&#96;; appending nil is a no-op. |
| [len](#fn-table-len) | `self: Table` | `!i64` | Lua &#96;#t&#96; honoring &#96;__len&#96;, which cannot yield; a non-integer result returns &#96;error.LuaError&#96;. |
| [rawLen](#fn-table-rawlen) | `self: Table` | `!i64` |  |
| [identity](#fn-table-identity) | `self: Table` | `!usize` | State-local, non-retaining token valid while rooted and until reset. |
| [getMetatable](#fn-table-getmetatable) | `self: Table` | `!?Table` | Ignores &#96;__metatable&#96;. The caller must &#96;deinit&#96; the result. |
| [setMetatable](#fn-table-setmetatable) | `self: Table, metatable: ?Table` | `!void` | Sets or removes the metatable, ignoring &#96;__metatable&#96; like &#96;lua_setmetatable&#96;. |
| [rawGet](#fn-table-rawget) | `self: Table, key: anytype, comptime T: type` | `!T` | A &#96;[]const u8&#96; result borrows VM memory; see &#96;Value.string&#96;. |
| [toSlice](#fn-table-toslice) | `self: Table, comptime T: type, allocator: std.mem.Allocator` | `![]T` | Reads raw entries &#96;1..rawLen()&#96;; holes fail with &#96;error.TypeMismatch&#96; unless &#96;T&#96; is optional. The caller frees the slice and deinits handle elements; string elements borrow VM memory. |
| [Entry](#type-table-entry) |  |  | String fields borrow VM memory; see &#96;Value.string&#96;. |
| [rawNext](#fn-table-rawnext) | `self: Table, key: anytype` | `!?Entry` | Lua &#96;next&#96;: start with null or &#96;.nil&#96;; deinit each entry. Prefer &#96;rawIterator&#96;. |
| [rawIterator](#fn-table-rawiterator) | `self: Table` | `!Iterator` | Raw-entry iterator like Lua &#96;next&#96;; the caller must &#96;deinit&#96; it. Existing fields may be assigned or cleared during traversal; adding keys is undefined. |
| [pairs](#fn-table-pairs) | `self: Table` | `!Iterator` | Iterator like Lua &#96;pairs(t)&#96;, honoring &#96;__pairs&#96;; its calls cannot yield. A closing value gets &#96;__close&#96; when iteration ends, fails, or &#96;close&#96; is called, but not on &#96;deinit&#96;. |
| [Iterator](#type-table-iterator) |  |  | Owns each returned &#96;Entry&#96; until the next &#96;next&#96;, &#96;close&#96;, or &#96;deinit&#96;; do not deinit entries. Reset invalidates the iterator. |

<a id="fn-table-deinit"></a>

### Table.deinit

```zig
pub fn deinit(self: *Table) void
```

References: [`Table`](#type-table)

<a id="fn-table-get"></a>

### Table.get

Reads `t[key]` honoring `__index`; metamethods cannot yield and fail with `error.LuaError`.
A `[]const u8` result borrows VM memory; see `Value.string`.

```zig
pub fn get(self: Table, key: anytype, comptime T: type) !T
```

References: [`Table`](#type-table)

<a id="fn-table-set"></a>

### Table.set

Assigns `t[key]` honoring `__newindex`; metamethods cannot yield.
A nil or NaN key returns `error.LuaError`.

```zig
pub fn set(self: Table, key: anytype, value: anytype) !void
```

References: [`Table`](#type-table)

<a id="fn-table-rawset"></a>

### Table.rawSet

Like `set` without `__newindex`; a nil or NaN key returns `error.LuaError`.

```zig
pub fn rawSet(self: Table, key: anytype, value: anytype) !void
```

References: [`Table`](#type-table)

<a id="fn-table-append"></a>

### Table.append

Raw-appends at `rawLen() + 1`; appending nil is a no-op.

```zig
pub fn append(self: Table, value: anytype) !void
```

References: [`Table`](#type-table)

<a id="fn-table-len"></a>

### Table.len

Lua `#t` honoring `__len`, which cannot yield; a non-integer result returns `error.LuaError`.

```zig
pub fn len(self: Table) !i64
```

References: [`Table`](#type-table)

<a id="fn-table-rawlen"></a>

### Table.rawLen

```zig
pub fn rawLen(self: Table) !i64
```

References: [`Table`](#type-table)

<a id="fn-table-identity"></a>

### Table.identity

[State](#type-state)-local, non-retaining token valid while rooted and until reset.

```zig
pub fn identity(self: Table) !usize
```

References: [`Table`](#type-table)

<a id="fn-table-getmetatable"></a>

### Table.getMetatable

Ignores `__metatable`. The caller must `deinit` the result.

```zig
pub fn getMetatable(self: Table) !?Table
```

References: [`Table`](#type-table)

<a id="fn-table-setmetatable"></a>

### Table.setMetatable

Sets or removes the metatable, ignoring `__metatable` like `lua_setmetatable`.

```zig
pub fn setMetatable(self: Table, metatable: ?Table) !void
```

References: [`Table`](#type-table)

<a id="fn-table-rawget"></a>

### Table.rawGet

A `[]const u8` result borrows VM memory; see `Value.string`.

```zig
pub fn rawGet(self: Table, key: anytype, comptime T: type) !T
```

References: [`Table`](#type-table)

<a id="fn-table-toslice"></a>

### Table.toSlice

Reads raw entries `1..rawLen()`; holes fail with `error.TypeMismatch` unless `T` is optional.
The caller frees the slice and deinits handle elements; string elements borrow VM memory.

```zig
pub fn toSlice(self: Table, comptime T: type, allocator: std.mem.Allocator) ![]T
```

References: [`Table`](#type-table)

<a id="type-table-entry"></a>

### Table.Entry

String fields borrow VM memory; see `Value.string`.

```zig
pub const Entry = struct {
    key: Value,
    value: Value,
};
```

#### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-entry-deinit) | `self: *Entry` | `void` | Only for &#96;rawNext&#96; entries; &#96;Iterator&#96; owns the entries it returns. |

<a id="fn-entry-deinit"></a>

#### Entry.deinit

Only for `rawNext` entries; `Iterator` owns the entries it returns.

```zig
pub fn deinit(self: *Entry) void
```

References: [`Entry`](#type-table-entry)

<a id="fn-table-rawnext"></a>

### Table.rawNext

Lua `next`: start with null or `.nil`; deinit each entry. Prefer `rawIterator`.

```zig
pub fn rawNext(self: Table, key: anytype) !?Entry
```

References: [`Table`](#type-table), [`Entry`](#type-table-entry)

<a id="fn-table-rawiterator"></a>

### Table.rawIterator

Raw-entry iterator like Lua `next`; the caller must `deinit` it. Existing fields may be
assigned or cleared during traversal; adding keys is undefined.

```zig
pub fn rawIterator(self: Table) !Iterator
```

References: [`Table`](#type-table), [`Iterator`](#type-table-iterator)

<a id="fn-table-pairs"></a>

### Table.pairs

[Iterator](#type-table-iterator) like Lua `pairs(t)`, honoring `__pairs`; its calls cannot yield. A closing value
gets `__close` when iteration ends, fails, or `close` is called, but not on `deinit`.

```zig
pub fn pairs(self: Table) !Iterator
```

References: [`Table`](#type-table), [`Iterator`](#type-table-iterator)

<a id="type-table-iterator"></a>

### Table.Iterator

Owns each returned `Entry` until the next `next`, `close`, or `deinit`; do not deinit entries.
Reset invalidates the iterator.

```zig
pub const Iterator = struct {
    state: *State,
    generation: u64,
    mode: Mode,
    roots: [slot_count]?usize = @splat(null),
    entry: ?Entry = null,
    done: bool = false,
};
```

#### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [next](#fn-iterator-next) | `self: *Iterator` | `!?Entry` | Returns the next entry, or null at the end; the previous entry is released first. |
| [close](#fn-iterator-close) | `self: *Iterator` | `!void` | Ends traversal early, running a pending closing value like &#96;break&#96;; still call &#96;deinit&#96;. |
| [deinit](#fn-iterator-deinit) | `self: *Iterator` | `void` | Releases roots without calling Lua. |

<a id="fn-iterator-next"></a>

#### Iterator.next

Returns the next entry, or null at the end; the previous entry is released first.

```zig
pub fn next(self: *Iterator) !?Entry
```

References: [`Iterator`](#type-table-iterator), [`Entry`](#type-table-entry)

<a id="fn-iterator-close"></a>

#### Iterator.close

Ends traversal early, running a pending closing value like `break`; still call `deinit`.

```zig
pub fn close(self: *Iterator) !void
```

References: [`Iterator`](#type-table-iterator)

<a id="fn-iterator-deinit"></a>

#### Iterator.deinit

Releases roots without calling Lua.

```zig
pub fn deinit(self: *Iterator) void
```

References: [`Iterator`](#type-table-iterator)

<a id="type-function"></a>

## Function

Rooted handle to a Lua function or loaded chunk.

```zig
pub const Function = struct {
    ref: Ref,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-function-deinit) | `self: *Function` | `void` |  |
| [call](#fn-function-call) | `self: Function, args: anytype, comptime R: type` | `!R` | Converts the first result, or a &#96;Tuple&#96;, to &#96;R&#96;; Lua failures return &#96;error.LuaError&#96;. &#96;[]const u8&#96; results borrow VM memory; see &#96;Value.string&#96;. |
| [callWith](#fn-function-callwith) | `self: Function, args: anytype, comptime R: type, options: CallOptions` | `!R` | &#96;call&#96; with &#96;CallOptions&#96;; on &#96;error.LuaError&#96; the handled error value and traceback are kept on the state. |
| [protectedCall](#fn-function-protectedcall) | `self: Function, args: anytype, comptime R: type` | `!CallResult(R)` | Like &#96;call&#96;, but returns Lua failures as &#96;CallResult.lua_error&#96;. |
| [protectedCallWith](#fn-function-protectedcallwith) | `self: Function, args: anytype, comptime R: type, options: CallOptions` | `!CallResult(R)` | &#96;protectedCall&#96; with &#96;CallOptions&#96;; a captured traceback is owned by the &#96;ErrorRef&#96;. |
| [dumpBytecode](#fn-function-dumpbytecode) | `self: Function, options: BytecodeDumpOptions` | `![]const u8` | Native callbacks return &#96;error.TypeMismatch&#96;. The caller frees the result with the state's allocator. |

<a id="fn-function-deinit"></a>

### Function.deinit

```zig
pub fn deinit(self: *Function) void
```

References: [`Function`](#type-function)

<a id="fn-function-call"></a>

### Function.call

Converts the first result, or a `Tuple`, to `R`; Lua failures return `error.LuaError`.
`[]const u8` results borrow VM memory; see `Value.string`.

```zig
pub fn call(self: Function, args: anytype, comptime R: type) !R
```

References: [`Function`](#type-function)

<a id="fn-function-callwith"></a>

### Function.callWith

`call` with `CallOptions`; on `error.LuaError` the handled error value and traceback
are kept on the state.

```zig
pub fn callWith(self: Function, args: anytype, comptime R: type, options: CallOptions) !R
```

References: [`Function`](#type-function), [`CallOptions`](#type-calloptions)

<a id="fn-function-protectedcall"></a>

### Function.protectedCall

Like `call`, but returns Lua failures as `CallResult.lua_error`.

```zig
pub fn protectedCall(self: Function, args: anytype, comptime R: type) !CallResult(R)
```

References: [`Function`](#type-function)

<a id="fn-function-protectedcallwith"></a>

### Function.protectedCallWith

`protectedCall` with `CallOptions`; a captured traceback is owned by the `ErrorRef`.

```zig
pub fn protectedCallWith(self: Function, args: anytype, comptime R: type, options: CallOptions) !CallResult(R)
```

References: [`Function`](#type-function), [`CallOptions`](#type-calloptions)

<a id="fn-function-dumpbytecode"></a>

### Function.dumpBytecode

Native callbacks return `error.TypeMismatch`.
The caller frees the result with the state's allocator.

```zig
pub fn dumpBytecode(self: Function, options: BytecodeDumpOptions) ![]const u8
```

References: [`Function`](#type-function), [`BytecodeDumpOptions`](#type-bytecodedumpoptions)

<a id="fn-userdata"></a>

## Userdata

Typed userdata handle for payload type `T`.

```zig
pub fn Userdata(comptime T: type) type
```

<a id="type-anyuserdata"></a>

## AnyUserdata

Rooted userdata handle with an unknown payload type.

```zig
pub const AnyUserdata = struct {
    ref: Ref,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-anyuserdata-deinit) | `self: *AnyUserdata` | `void` |  |
| [as](#fn-anyuserdata-as) | `self: AnyUserdata, comptime T: type` | `!Userdata(T)` | Returns a new typed handle after checking the payload type. |

<a id="fn-anyuserdata-deinit"></a>

### AnyUserdata.deinit

```zig
pub fn deinit(self: *AnyUserdata) void
```

References: [`AnyUserdata`](#type-anyuserdata)

<a id="fn-anyuserdata-as"></a>

### AnyUserdata.as

Returns a new typed handle after checking the payload type.

```zig
pub fn as(self: AnyUserdata, comptime T: type) !Userdata(T)
```

References: [`AnyUserdata`](#type-anyuserdata)

<a id="fn-callresult"></a>

## CallResult

Result of protected calls and coroutine operations.

```zig
pub fn CallResult(comptime R: type) type
```

<a id="type-errorref"></a>

## ErrorRef

Rooted handle to a Lua error value.

```zig
pub const ErrorRef = struct {
    ref: Ref,
    /// Owned traceback; read it with `traceback`.
    traceback_text: ?[]const u8 = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-errorref-deinit) | `self: *ErrorRef` | `void` |  |
| [traceback](#fn-errorref-traceback) | `self: ErrorRef` | `?[]const u8` | Traceback when &#96;CallOptions.traceback&#96; was set, formatted like &#96;debug.traceback&#96;; valid until &#96;deinit&#96;. |
| [value](#fn-errorref-value) | `self: ErrorRef` | `!Value` |  |
| [message](#fn-errorref-message) | `self: ErrorRef` | `![]const u8` | Formats the error value; the caller frees it with the state's allocator. |

<a id="fn-errorref-deinit"></a>

### ErrorRef.deinit

```zig
pub fn deinit(self: *ErrorRef) void
```

References: [`ErrorRef`](#type-errorref)

<a id="fn-errorref-traceback"></a>

### ErrorRef.traceback

Traceback when `CallOptions.traceback` was set, formatted like `debug.traceback`;
valid until `deinit`.

```zig
pub fn traceback(self: ErrorRef) ?[]const u8
```

References: [`ErrorRef`](#type-errorref)

<a id="fn-errorref-value"></a>

### ErrorRef.value

```zig
pub fn value(self: ErrorRef) !Value
```

References: [`ErrorRef`](#type-errorref), [`Value`](#type-value)

<a id="fn-errorref-message"></a>

### ErrorRef.message

Formats the error value; the caller frees it with the state's allocator.

```zig
pub fn message(self: ErrorRef) ![]const u8
```

References: [`ErrorRef`](#type-errorref)

<a id="type-value"></a>

## Value

Dynamic Lua value; handle variants are rooted and released by `deinit`.

```zig
pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    /// Borrowed, unrooted VM bytes, valid while Lua can reach the string. Once unreachable, any
    /// GC-capable call may free them; `deinit` and `reset` always do. Copy or use `Ref` to keep.
    string: []const u8,
    table: Table,
    function: Function,
    coroutine: Coroutine,
    userdata: AnyUserdata,
    /// Lua value kind not represented by the high-level API.
    unsupported,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-value-deinit) | `self: *Value` | `void` |  |

<a id="fn-value-deinit"></a>

### Value.deinit

```zig
pub fn deinit(self: *Value) void
```

References: [`Value`](#type-value)

<a id="fn-tuple"></a>

## Tuple

Converts multiple Lua return values.

```zig
pub fn Tuple(comptime types: []const type) type
```

<a id="type-context"></a>

## Context

Callback context for functions registered with `State.register`.

```zig
pub const Context = struct {
    lua: *State,
    raw: *runtime.ApiCallbackContext,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [state](#fn-context-state) | `self: *Context` | `*State` |  |
| [argCount](#fn-context-argcount) | `self: *Context` | `usize` |  |
| [arg](#fn-context-arg) | `self: *Context, index: usize, comptime T: type` | `!T` | A &#96;[]const u8&#96; argument borrows VM memory until the callback returns. |
| [optionalArg](#fn-context-optionalarg) | `self: *Context, index: usize, comptime T: type` | `!?T` | Returns null when absent or &#96;nil&#96;. |
| [pushReturn](#fn-context-pushreturn) | `self: *Context, value: anytype` | `!void` |  |
| [returnValues](#fn-context-returnvalues) | `self: *Context, values: anytype` | `!void` | Replaces callback returns; tuples like &#96;.{ a, b }&#96; return multiple values. |
| [raise](#fn-context-raise) | `self: *Context, value: anytype` | `error` | Raises &#96;value&#96; as the Lua error object. |
| [coroutine](#fn-context-coroutine) | `self: *Context` | `!Coroutine` | Rooted handle to this callback's coroutine, usable beyond the callback. |
| [isYieldable](#fn-context-isyieldable) | `self: *Context` | `bool` | Reports whether this callback can yield across the current native boundary. |
| [yield](#fn-context-yield) | `self: *Context, values: anytype` | `error` | Terminal yield: &#96;return ctx.yield(.{values});&#96;. Defers run before suspension; resume continues Lua with the resume arguments without reentering the Zig body. |
| [coroutineIdentity](#fn-context-coroutineidentity) | `self: *Context` | `usize` | Coroutine token valid only during this callback and until reset. |
| [callNonYielding](#fn-context-callnonyielding) | `self: *Context, function: Function, args: anytype, comptime R: type` | `!R` | Calls Lua on this coroutine within its budget; yielding is forbidden and errors propagate. |

<a id="fn-context-state"></a>

### Context.state

```zig
pub fn state(self: *Context) *State
```

References: [`Context`](#type-context), [`State`](#type-state)

<a id="fn-context-argcount"></a>

### Context.argCount

```zig
pub fn argCount(self: *Context) usize
```

References: [`Context`](#type-context)

<a id="fn-context-arg"></a>

### Context.arg

A `[]const u8` argument borrows VM memory until the callback returns.

```zig
pub fn arg(self: *Context, index: usize, comptime T: type) !T
```

References: [`Context`](#type-context)

<a id="fn-context-optionalarg"></a>

### Context.optionalArg

Returns null when absent or `nil`.

```zig
pub fn optionalArg(self: *Context, index: usize, comptime T: type) !?T
```

References: [`Context`](#type-context)

<a id="fn-context-pushreturn"></a>

### Context.pushReturn

```zig
pub fn pushReturn(self: *Context, value: anytype) !void
```

References: [`Context`](#type-context)

<a id="fn-context-returnvalues"></a>

### Context.returnValues

Replaces callback returns; tuples like `.{ a, b }` return multiple values.

```zig
pub fn returnValues(self: *Context, values: anytype) !void
```

References: [`Context`](#type-context)

<a id="fn-context-raise"></a>

### Context.raise

Raises `value` as the Lua error object.

```zig
pub fn raise(self: *Context, value: anytype) error{ LuaError, OutOfMemory, InvalidHandle }
```

References: [`Context`](#type-context)

<a id="fn-context-coroutine"></a>

### Context.coroutine

Rooted handle to this callback's coroutine, usable beyond the callback.

```zig
pub fn coroutine(self: *Context) !Coroutine
```

References: [`Context`](#type-context), [`Coroutine`](#type-coroutine)

<a id="fn-context-isyieldable"></a>

### Context.isYieldable

Reports whether this callback can yield across the current native boundary.

```zig
pub fn isYieldable(self: *Context) bool
```

References: [`Context`](#type-context)

<a id="fn-context-yield"></a>

### Context.yield

Terminal yield: `return ctx.yield(.{values});`. Defers run before suspension; resume
continues Lua with the resume arguments without reentering the Zig body.

```zig
pub fn yield(self: *Context, values: anytype) error{ HostCallbackYield, LuaError, OutOfMemory, InvalidHandle }
```

References: [`Context`](#type-context)

<a id="fn-context-coroutineidentity"></a>

### Context.coroutineIdentity

[Coroutine](#type-coroutine) token valid only during this callback and until reset.

```zig
pub fn coroutineIdentity(self: *Context) usize
```

References: [`Context`](#type-context)

<a id="fn-context-callnonyielding"></a>

### Context.callNonYielding

Calls Lua on this coroutine within its budget; yielding is forbidden and errors propagate.

```zig
pub fn callNonYielding(self: *Context, function: Function, args: anytype, comptime R: type) !R
```

References: [`Context`](#type-context), [`Function`](#type-function)

<a id="alias-coroutinestatus"></a>

## CoroutineStatus

```zig
pub const CoroutineStatus = runtime_types.ThreadStatus;
```

<a id="fn-resumeresult"></a>

## ResumeResult

Converts only the active branch; strings are borrowed and handles released by `deinit`.
Conversion failure does not rewind execution.

```zig
pub fn ResumeResult(comptime Y: type, comptime R: type) type
```

<a id="type-coroutine"></a>

## Coroutine

Rooted coroutine handle; copies are not owners. Reset invalidates it; deinit before its state.

```zig
pub const Coroutine = struct {
    ref: Ref,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-coroutine-deinit) | `self: *Coroutine` | `void` | Releases only the root; use &#96;close&#96; to unwind pending frames. |
| [resumeCoroutine](#fn-coroutine-resumecoroutine) | `self: Coroutine, args: anytype, comptime Y: type, comptime R: type` | `!ResumeResult(Y, R)` | Converts yields to &#96;Y&#96; and returns to &#96;R&#96;; Lua failures return &#96;error.LuaError&#96;. |
| [protectedResume](#fn-coroutine-protectedresume) | `self: Coroutine, args: anytype, comptime Y: type, comptime R: type` | `!CallResult(ResumeResult(Y, R))` | Like &#96;resumeCoroutine&#96;, returning Lua errors as an &#96;ErrorRef&#96;. |
| [status](#fn-coroutine-status) | `self: Coroutine` | `!CoroutineStatus` |  |
| [identity](#fn-coroutine-identity) | `self: Coroutine` | `!usize` | State-local token valid while rooted and until reset. |
| [close](#fn-coroutine-close) | `self: Coroutine` | `!void` | Unwinds pending frames and &#96;__close&#96; handlers; rejects main, running, and normal coroutines. |
| [protectedClose](#fn-coroutine-protectedclose) | `self: Coroutine` | `!CallResult(void)` | Like &#96;close&#96;, returning Lua errors as an &#96;ErrorRef&#96; the caller must &#96;deinit&#96;. |

<a id="fn-coroutine-deinit"></a>

### Coroutine.deinit

Releases only the root; use `close` to unwind pending frames.

```zig
pub fn deinit(self: *Coroutine) void
```

References: [`Coroutine`](#type-coroutine)

<a id="fn-coroutine-resumecoroutine"></a>

### Coroutine.resumeCoroutine

Converts yields to `Y` and returns to `R`; Lua failures return `error.LuaError`.

```zig
pub fn resumeCoroutine(self: Coroutine, args: anytype, comptime Y: type, comptime R: type) !ResumeResult(Y, R)
```

References: [`Coroutine`](#type-coroutine)

<a id="fn-coroutine-protectedresume"></a>

### Coroutine.protectedResume

Like `resumeCoroutine`, returning Lua errors as an `ErrorRef`.

```zig
pub fn protectedResume(self: Coroutine, args: anytype, comptime Y: type, comptime R: type) !CallResult(ResumeResult(Y, R))
```

References: [`Coroutine`](#type-coroutine)

<a id="fn-coroutine-status"></a>

### Coroutine.status

```zig
pub fn status(self: Coroutine) !CoroutineStatus
```

References: [`Coroutine`](#type-coroutine), [`CoroutineStatus`](#alias-coroutinestatus)

<a id="fn-coroutine-identity"></a>

### Coroutine.identity

[State](#type-state)-local token valid while rooted and until reset.

```zig
pub fn identity(self: Coroutine) !usize
```

References: [`Coroutine`](#type-coroutine)

<a id="fn-coroutine-close"></a>

### Coroutine.close

Unwinds pending frames and `__close` handlers; rejects main, running, and normal coroutines.

```zig
pub fn close(self: Coroutine) !void
```

References: [`Coroutine`](#type-coroutine)

<a id="fn-coroutine-protectedclose"></a>

### Coroutine.protectedClose

Like `close`, returning Lua errors as an `ErrorRef` the caller must `deinit`.

```zig
pub fn protectedClose(self: Coroutine) !CallResult(void)
```

References: [`Coroutine`](#type-coroutine)

