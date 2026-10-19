# root

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
- [runtime.state](runtime/state.md)
- [stdlib](stdlib.md)
- [stdlib.base](stdlib/base.md)
- [runtime.call](runtime/call.md)
- [stdlib.static_strings](stdlib/static_strings.md)
- [runtime.table_index](runtime/table_index.md)
- [runtime.value](runtime/value.md)
- [runtime.number_format](runtime/number_format.md)
- [runtime.coroutine](runtime/coroutine.md)
- [runtime.debug](runtime/debug.md)
- [runtime.metatable](runtime/metatable.md)
- [runtime.rollback](runtime/rollback.md)
- [runtime.strings](runtime/strings.md)
- [runtime.operators](runtime/operators.md)
- [runtime.failure](runtime/failure.md)
- [runtime.io](runtime/io.md)
- [runtime.host](runtime/host.md)
- [runtime.load](runtime/load.md)
- [runtime.vm](runtime/vm.md)
- [runtime.gc](runtime/gc.md)
- [runtime.entry](runtime/entry.md)
- [runtime.system](runtime/system.md)
- [runtime.timezone](runtime/timezone.md)
- [runtime.upvalue](runtime/upvalue.md)
- [runtime.index](runtime/index.md)
- [stdlib.table](stdlib/table.md)
- [stdlib.string](stdlib/string.md)
- [stdlib.string.format](stdlib/string/format.md)
- [stdlib.string.pack](stdlib/string/pack.md)
- [stdlib.string.pattern](stdlib/string/pattern.md)
- [stdlib.math](stdlib/math.md)
- [stdlib.utf8](stdlib/utf8.md)
- [stdlib.coroutine](stdlib/coroutine.md)
- [stdlib.debug](stdlib/debug.md)
- [stdlib.io](stdlib/io.md)
- [stdlib.os](stdlib/os.md)
- [stdlib.package](stdlib/package.md)
- [stdlib.json](stdlib/json.md)
- [stdlib.zerde_lua](stdlib/zerde_lua.md)
- [stdlib.toml](stdlib/toml.md)
- [stdlib.msgpack](stdlib/msgpack.md)
- [stdlib.csv](stdlib/csv.md)
- [stdlib.fs](stdlib/fs.md)
- [runtime.budget](runtime/budget.md)
- [runtime.object_pool](runtime/object_pool.md)
- [runtime.execute](runtime/execute.md)
- [testing.process](testing/process.md)
- [runtime.tests](runtime/tests.md)
- [runtime.internal](runtime/internal.md)
- [runtime.native_fn](runtime/native_fn.md)
- [compile.compiler](compile/compiler.md)
- [compile.fold](compile/fold.md)
- [compile.disasm](compile/disasm.md)
- [api](api.md)
- [api.callbacks](api/callbacks.md)
- [api.convert](api/convert.md)
- [api.errors](api/errors.md)
- [api.handle](api/handle.md)
- [api.state](api/state.md)
- [runtime.snapshot](runtime/snapshot.md)
- [api.capabilities](api/capabilities.md)
- [api.options](api/options.md)
- [api.function](api/function.md)
- [api.table](api/table.md)
- [api.value](api/value.md)
- [api.userdata](api/userdata.md)
- [api.context](api/context.md)
- [api.coroutine](api/coroutine.md)
- [api.snapshot](api/snapshot.md)
- [api.memory_limit](api/memory_limit.md)
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
- [testing.bench.system](testing/bench/system.md)
- [testing.diff_runner](testing/diff_runner.md)
- [testing.fixtures](testing/fixtures.md)
- [testing.expected_failures](testing/expected_failures.md)
- [testing.metadata](testing/metadata.md)
- [testing.normalizer](testing/normalizer.md)
- [testing.parallel](testing/parallel.md)
- [testing.extension_runner](testing/extension_runner.md)
- [testing.official_suite](testing/official_suite.md)

</details>

## Constants

- [version](#const-version)
- [lua_target_version](#const-lua_target_version)

## Aliases

- [State](#alias-state)
- [Snapshot](#alias-snapshot)
- [UserdataSnapshotHooks](#alias-userdatasnapshothooks)
- [Options](#alias-options)
- [GcMode](#alias-gcmode)
- [GcParam](#alias-gcparam)
- [GcParams](#alias-gcparams)
- [GcOptions](#alias-gcoptions)
- [GcBudget](#alias-gcbudget)
- [GcStepResult](#alias-gcstepresult)
- [Stdlib](#alias-stdlib)
- [LibrarySet](#alias-libraryset)
- [Value](#alias-value)
- [Ref](#alias-ref)
- [Table](#alias-table)
- [Function](#alias-function)
- [Coroutine](#alias-coroutine)
- [CoroutineStatus](#alias-coroutinestatus)
- [ResumeResult](#alias-resumeresult)
- [CallResult](#alias-callresult)
- [ErrorRef](#alias-errorref)
- [CallOptions](#alias-calloptions)
- [InterruptHandle](#alias-interrupthandle)
- [Context](#alias-context)
- [Error](#alias-error)
- [BytecodeLoadOptions](#alias-bytecodeloadoptions)
- [BytecodeDumpOptions](#alias-bytecodedumpoptions)
- [Tuple](#alias-tuple)
- [HostFn](#alias-hostfn)
- [Userdata](#alias-userdata)
- [AnyUserdata](#alias-anyuserdata)
- [MemoryFile](#alias-memoryfile)
- [MemoryFilesystem](#alias-memoryfilesystem)
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
- [ProcessCapability](#alias-processcapability)
- [CustomProcess](#alias-customprocess)
- [ProcessResult](#alias-processresult)
- [ProcessStatus](#alias-processstatus)
- [OutputFlush](#alias-outputflush)

## Imports

- [frontend](#import-frontend) `@import("frontend.zig")`
- [compile](#import-compile) `@import("compile.zig")`
- [errors](#import-errors) `@import("errors.zig")`
- [api](#import-api) `@import("api.zig")`
- [runtime](#import-runtime) `@import("runtime.zig")`
- [stdlib](#import-stdlib) `@import("stdlib.zig")`
- [testing](#import-testing) `@import("testing.zig")`

<a id="const-version"></a>

## version

```zig
pub const version = "0.7.2";
```

<a id="const-lua_target_version"></a>

## lua_target_version

```zig
pub const lua_target_version = "Lua 5.5";
```

<a id="import-frontend"></a>

## frontend

```zig
pub const frontend = @import("frontend.zig");
```

<a id="import-compile"></a>

## compile

```zig
pub const compile = @import("compile.zig");
```

<a id="import-errors"></a>

## errors

```zig
pub const errors = @import("errors.zig");
```

<a id="import-api"></a>

## api

```zig
pub const api = @import("api.zig");
```

<a id="import-runtime"></a>

## runtime

```zig
pub const runtime = @import("runtime.zig");
```

<a id="import-stdlib"></a>

## stdlib

```zig
pub const stdlib = @import("stdlib.zig");
```

<a id="import-testing"></a>

## testing

```zig
pub const testing = @import("testing.zig");
```

<a id="alias-state"></a>

## State

```zig
pub const State = api.State;
```

References: [`api.State`](api.md#alias-state)

<a id="alias-snapshot"></a>

## Snapshot

```zig
pub const Snapshot = api.Snapshot;
```

References: [`api.Snapshot`](api.md#alias-snapshot)

<a id="alias-userdatasnapshothooks"></a>

## UserdataSnapshotHooks

```zig
pub const UserdataSnapshotHooks = api.UserdataSnapshotHooks;
```

References: [`api.UserdataSnapshotHooks`](api.md#alias-userdatasnapshothooks)

<a id="alias-options"></a>

## Options

```zig
pub const Options = api.Options;
```

References: [`api.Options`](api.md#alias-options)

<a id="alias-gcmode"></a>

## GcMode

```zig
pub const GcMode = api.GcMode;
```

References: [`api.GcMode`](api.md#alias-gcmode)

<a id="alias-gcparam"></a>

## GcParam

```zig
pub const GcParam = api.GcParam;
```

References: [`api.GcParam`](api.md#alias-gcparam)

<a id="alias-gcparams"></a>

## GcParams

```zig
pub const GcParams = api.GcParams;
```

References: [`api.GcParams`](api.md#alias-gcparams)

<a id="alias-gcoptions"></a>

## GcOptions

```zig
pub const GcOptions = api.GcOptions;
```

References: [`api.GcOptions`](api.md#alias-gcoptions)

<a id="alias-gcbudget"></a>

## GcBudget

```zig
pub const GcBudget = api.GcBudget;
```

References: [`api.GcBudget`](api.md#alias-gcbudget)

<a id="alias-gcstepresult"></a>

## GcStepResult

```zig
pub const GcStepResult = api.GcStepResult;
```

References: [`api.GcStepResult`](api.md#alias-gcstepresult)

<a id="alias-stdlib"></a>

## Stdlib

```zig
pub const Stdlib = api.Stdlib;
```

References: [`api.Stdlib`](api.md#alias-stdlib)

<a id="alias-libraryset"></a>

## LibrarySet

```zig
pub const LibrarySet = api.LibrarySet;
```

References: [`api.LibrarySet`](api.md#alias-libraryset)

<a id="alias-value"></a>

## Value

```zig
pub const Value = api.Value;
```

References: [`api.Value`](api.md#alias-value)

<a id="alias-ref"></a>

## Ref

```zig
pub const Ref = api.Ref;
```

References: [`api.Ref`](api.md#alias-ref)

<a id="alias-table"></a>

## Table

```zig
pub const Table = api.Table;
```

References: [`api.Table`](api.md#alias-table)

<a id="alias-function"></a>

## Function

```zig
pub const Function = api.Function;
```

References: [`api.Function`](api.md#alias-function)

<a id="alias-coroutine"></a>

## Coroutine

```zig
pub const Coroutine = api.Coroutine;
```

References: [`api.Coroutine`](api.md#alias-coroutine)

<a id="alias-coroutinestatus"></a>

## CoroutineStatus

```zig
pub const CoroutineStatus = api.CoroutineStatus;
```

References: [`api.CoroutineStatus`](api.md#alias-coroutinestatus)

<a id="alias-resumeresult"></a>

## ResumeResult

```zig
pub const ResumeResult = api.ResumeResult;
```

References: [`api.ResumeResult`](api.md#alias-resumeresult)

<a id="alias-callresult"></a>

## CallResult

```zig
pub const CallResult = api.CallResult;
```

References: [`api.CallResult`](api.md#alias-callresult)

<a id="alias-errorref"></a>

## ErrorRef

```zig
pub const ErrorRef = api.ErrorRef;
```

References: [`api.ErrorRef`](api.md#alias-errorref)

<a id="alias-calloptions"></a>

## CallOptions

```zig
pub const CallOptions = api.CallOptions;
```

References: [`api.CallOptions`](api.md#alias-calloptions)

<a id="alias-interrupthandle"></a>

## InterruptHandle

```zig
pub const InterruptHandle = api.InterruptHandle;
```

References: [`api.InterruptHandle`](api.md#alias-interrupthandle)

<a id="alias-context"></a>

## Context

```zig
pub const Context = api.Context;
```

References: [`api.Context`](api.md#alias-context)

<a id="alias-error"></a>

## Error

```zig
pub const Error = api.Error;
```

References: [`api.Error`](api.md#alias-error)

<a id="alias-bytecodeloadoptions"></a>

## BytecodeLoadOptions

```zig
pub const BytecodeLoadOptions = api.BytecodeLoadOptions;
```

References: [`api.BytecodeLoadOptions`](api.md#alias-bytecodeloadoptions)

<a id="alias-bytecodedumpoptions"></a>

## BytecodeDumpOptions

```zig
pub const BytecodeDumpOptions = api.BytecodeDumpOptions;
```

References: [`api.BytecodeDumpOptions`](api.md#alias-bytecodedumpoptions)

<a id="alias-tuple"></a>

## Tuple

```zig
pub const Tuple = api.Tuple;
```

References: [`api.Tuple`](api.md#alias-tuple)

<a id="alias-hostfn"></a>

## HostFn

```zig
pub const HostFn = api.HostFn;
```

References: [`api.HostFn`](api.md#alias-hostfn)

<a id="alias-userdata"></a>

## Userdata

```zig
pub const Userdata = api.Userdata;
```

References: [`api.Userdata`](api.md#alias-userdata)

<a id="alias-anyuserdata"></a>

## AnyUserdata

```zig
pub const AnyUserdata = api.AnyUserdata;
```

References: [`api.AnyUserdata`](api.md#alias-anyuserdata)

<a id="alias-memoryfile"></a>

## MemoryFile

```zig
pub const MemoryFile = api.MemoryFile;
```

References: [`api.MemoryFile`](api.md#alias-memoryfile)

<a id="alias-memoryfilesystem"></a>

## MemoryFilesystem

```zig
pub const MemoryFilesystem = api.MemoryFilesystem;
```

References: [`api.MemoryFilesystem`](api.md#alias-memoryfilesystem)

<a id="alias-filesystemcapability"></a>

## FilesystemCapability

```zig
pub const FilesystemCapability = api.FilesystemCapability;
```

References: [`api.FilesystemCapability`](api.md#alias-filesystemcapability)

<a id="alias-customfilesystem"></a>

## CustomFilesystem

```zig
pub const CustomFilesystem = api.CustomFilesystem;
```

References: [`api.CustomFilesystem`](api.md#alias-customfilesystem)

<a id="alias-hostdirectory"></a>

## HostDirectory

```zig
pub const HostDirectory = api.HostDirectory;
```

References: [`api.HostDirectory`](api.md#alias-hostdirectory)

<a id="alias-filesystemfilekind"></a>

## FilesystemFileKind

```zig
pub const FilesystemFileKind = api.FilesystemFileKind;
```

References: [`api.FilesystemFileKind`](api.md#alias-filesystemfilekind)

<a id="alias-filesystemfilestat"></a>

## FilesystemFileStat

```zig
pub const FilesystemFileStat = api.FilesystemFileStat;
```

References: [`api.FilesystemFileStat`](api.md#alias-filesystemfilestat)

<a id="alias-filesystemdirectoryentry"></a>

## FilesystemDirectoryEntry

```zig
pub const FilesystemDirectoryEntry = api.FilesystemDirectoryEntry;
```

References: [`api.FilesystemDirectoryEntry`](api.md#alias-filesystemdirectoryentry)

<a id="alias-deinitfilesystemdirectoryentries"></a>

## deinitFilesystemDirectoryEntries

```zig
pub const deinitFilesystemDirectoryEntries = api.deinitFilesystemDirectoryEntries;
```

References: [`api.deinitFilesystemDirectoryEntries`](api.md#alias-deinitfilesystemdirectoryentries)

<a id="alias-environmentcapability"></a>

## EnvironmentCapability

```zig
pub const EnvironmentCapability = api.EnvironmentCapability;
```

References: [`api.EnvironmentCapability`](api.md#alias-environmentcapability)

<a id="alias-customenvironment"></a>

## CustomEnvironment

```zig
pub const CustomEnvironment = api.CustomEnvironment;
```

References: [`api.CustomEnvironment`](api.md#alias-customenvironment)

<a id="alias-clockcapability"></a>

## ClockCapability

```zig
pub const ClockCapability = api.ClockCapability;
```

References: [`api.ClockCapability`](api.md#alias-clockcapability)

<a id="alias-customclock"></a>

## CustomClock

```zig
pub const CustomClock = api.CustomClock;
```

References: [`api.CustomClock`](api.md#alias-customclock)

<a id="alias-processcapability"></a>

## ProcessCapability

```zig
pub const ProcessCapability = api.ProcessCapability;
```

References: [`api.ProcessCapability`](api.md#alias-processcapability)

<a id="alias-customprocess"></a>

## CustomProcess

```zig
pub const CustomProcess = api.CustomProcess;
```

References: [`api.CustomProcess`](api.md#alias-customprocess)

<a id="alias-processresult"></a>

## ProcessResult

```zig
pub const ProcessResult = api.ProcessResult;
```

References: [`api.ProcessResult`](api.md#alias-processresult)

<a id="alias-processstatus"></a>

## ProcessStatus

```zig
pub const ProcessStatus = api.ProcessStatus;
```

References: [`api.ProcessStatus`](api.md#alias-processstatus)

<a id="alias-outputflush"></a>

## OutputFlush

```zig
pub const OutputFlush = api.OutputFlush;
```

References: [`api.OutputFlush`](api.md#alias-outputflush)

