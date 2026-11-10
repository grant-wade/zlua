# api

## Navigation

- [API Index](README.md)
- Submodules: [api.analyze](api/analyze.md), [api.callbacks](api/callbacks.md), [api.convert](api/convert.md), [api.errors](api/errors.md), [api.handle](api/handle.md), [api.state](api/state.md), [api.capabilities](api/capabilities.md), [api.options](api/options.md), [api.function](api/function.md), [api.table](api/table.md), [api.value](api/value.md), [api.userdata](api/userdata.md), [api.namespace](api/namespace.md), [api.context](api/context.md), [api.decode](api/decode.md), [api.coroutine](api/coroutine.md), [api.string](api/string.md), [api.snapshot](api/snapshot.md), [api.memory_limit](api/memory_limit.md)

<details>
<summary>All documents</summary>

- [root](root.md)
- [api](api.md)
- [api.analyze](api/analyze.md)
- [compile](compile.md)
- [errors](errors.md)
- [frontend.source](frontend/source.md)
- [frontend.token](frontend/token.md)
- [frontend](frontend.md)
- [frontend.diagnostic](frontend/diagnostic.md)
- [frontend.lexer](frontend/lexer.md)
- [stack_guard](stack_guard.md)
- [frontend.ast](frontend/ast.md)
- [frontend.parser](frontend/parser.md)
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
- [runtime.budget](runtime/budget.md)
- [runtime.failure](runtime/failure.md)
- [runtime.debug](runtime/debug.md)
- [runtime.io](runtime/io.md)
- [runtime.host](runtime/host.md)
- [runtime.value](runtime/value.md)
- [runtime.number_format](runtime/number_format.md)
- [stdlib.static_strings](stdlib/static_strings.md)
- [runtime.table_index](runtime/table_index.md)
- [runtime.metatable](runtime/metatable.md)
- [runtime.rollback](runtime/rollback.md)
- [runtime.strings](runtime/strings.md)
- [runtime.operators](runtime/operators.md)
- [runtime.vm](runtime/vm.md)
- [runtime.gc](runtime/gc.md)
- [runtime.entry](runtime/entry.md)
- [runtime.coroutine](runtime/coroutine.md)
- [runtime.load](runtime/load.md)
- [runtime.upvalue](runtime/upvalue.md)
- [runtime.system](runtime/system.md)
- [runtime.timezone](runtime/timezone.md)
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
- [stdlib.data](stdlib/data.md)
- [stdlib.datetime](stdlib/datetime.md)
- [stdlib.toml](stdlib/toml.md)
- [stdlib.msgpack](stdlib/msgpack.md)
- [stdlib.csv](stdlib/csv.md)
- [stdlib.fs](stdlib/fs.md)
- [runtime.object_pool](runtime/object_pool.md)
- [runtime.execute](runtime/execute.md)
- [testing.process](testing/process.md)
- [runtime.tests](runtime/tests.md)
- [runtime.internal](runtime/internal.md)
- [runtime.native_fn](runtime/native_fn.md)
- [compile.compiler](compile/compiler.md)
- [compile.fold](compile/fold.md)
- [compile.disasm](compile/disasm.md)
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
- [api.namespace](api/namespace.md)
- [api.context](api/context.md)
- [api.decode](api/decode.md)
- [api.coroutine](api/coroutine.md)
- [api.string](api/string.md)
- [api.snapshot](api/snapshot.md)
- [api.memory_limit](api/memory_limit.md)
- [testing](testing.md)
- [testing.clua](testing/clua.md)
- [testing.bench_runner](testing/bench_runner.md)
- [testing.bench.options](testing/bench/options.md)
- [testing.bench.results](testing/bench/results.md)
- [testing.bench.stats](testing/bench/stats.md)
- [testing.bench.report](testing/bench/report.md)
- [testing.bench.api](testing/bench/api.md)
- [testing.bench.allocation](testing/bench/allocation.md)
- [testing.bench.process](testing/bench/process.md)
- [testing.bench.fixtures](testing/bench/fixtures.md)
- [testing.bench.legacy_process](testing/bench/legacy_process.md)
- [testing.bench.startup](testing/bench/startup.md)
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
- [testing.format_suite](testing/format_suite.md)
- [testing.official_suite](testing/official_suite.md)
- [testing.sandbox_runner](testing/sandbox_runner.md)
- [testing.generators](testing/generators.md)

</details>

## Overview

Zig-native embedding API for zlua: a Lua 5.5 state driven with Zig values,
explicit host capabilities, rooted handles, and Zig errors.

Rooted handles (`String`, `Table`, `Function`, `Coroutine`, `Ref`, `Userdata(T)`,
`AnyUserdata`, `ErrorRef`, and `Value`s holding them) must be released with `deinit`. `State.reset`
invalidates prior handles and borrowed VM slices. The `runtime` module is internal.
See `docs/embedding.md` for capabilities, error handling, snapshots, and ownership.

## Aliases

- [Error](#alias-error)
- [UnsupportedOption](#alias-unsupportedoption)
- [ConversionError](#alias-conversionerror)
- [ErrorRef](#alias-errorref)
- [State](#alias-state)
- [HostData](#alias-hostdata)
- [InterruptHandle](#alias-interrupthandle)
- [Snapshot](#alias-snapshot)
- [LibrarySet](#alias-libraryset)
- [Stdlib](#alias-stdlib)
- [Limits](#alias-limits)
- [CallOptions](#alias-calloptions)
- [ResumeOptions](#alias-resumeoptions)
- [InstructionBudget](#alias-instructionbudget)
- [GcMode](#alias-gcmode)
- [GcParam](#alias-gcparam)
- [GcParams](#alias-gcparams)
- [GcOptions](#alias-gcoptions)
- [DebugOptions](#alias-debugoptions)
- [Options](#alias-options)
- [LoadMode](#alias-loadmode)
- [LoadOptions](#alias-loadoptions)
- [BytecodeLoadOptions](#alias-bytecodeloadoptions)
- [BytecodeDumpOptions](#alias-bytecodedumpoptions)
- [TableOptions](#alias-tableoptions)
- [GcStepResult](#alias-gcstepresult)
- [MemoryFile](#alias-memoryfile)
- [MemoryFilesystem](#alias-memoryfilesystem)
- [OutputFlush](#alias-outputflush)
- [IoCapability](#alias-iocapability)
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
- [Capabilities](#alias-capabilities)
- [Value](#alias-value)
- [Ref](#alias-ref)
- [String](#alias-string)
- [HandleScope](#alias-handlescope)
- [Table](#alias-table)
- [Function](#alias-function)
- [Coroutine](#alias-coroutine)
- [CoroutineStatus](#alias-coroutinestatus)
- [ResumeResult](#alias-resumeresult)
- [Userdata](#alias-userdata)
- [AnyUserdata](#alias-anyuserdata)
- [UserdataOptions](#alias-userdataoptions)
- [UserdataType](#alias-userdatatype)
- [UserdataSnapshotHooks](#alias-userdatasnapshothooks)
- [Analysis](#alias-analysis)
- [GlobalUse](#alias-globaluse)
- [analyze](#alias-analyze)
- [Decoder](#alias-decoder)
- [DecodeError](#alias-decodeerror)
- [DecodeOptions](#alias-decodeoptions)
- [Diagnostic](#alias-diagnostic)
- [FieldOptions](#alias-fieldoptions)
- [decode](#alias-decode)
- [defaultValue](#alias-defaultvalue)
- [fieldKeys](#alias-fieldkeys)
- [fieldOptions](#alias-fieldoptions)
- [HostFn](#alias-hostfn)
- [Context](#alias-context)
- [Host](#alias-host)
- [Caller](#alias-caller)

## Imports

- [deinit](#import-deinit) `@import("api/convert.zig")`

<a id="alias-error"></a>

## Error

```zig
pub const Error = errors.Error;
```

References: [`errors.Error`](api/errors.md#type-error)

<a id="alias-unsupportedoption"></a>

## UnsupportedOption

```zig
pub const UnsupportedOption = errors.UnsupportedOption;
```

References: [`errors.UnsupportedOption`](api/errors.md#type-unsupportedoption)

<a id="alias-conversionerror"></a>

## ConversionError

```zig
pub const ConversionError = errors.ConversionError;
```

References: [`errors.ConversionError`](api/errors.md#type-conversionerror)

<a id="alias-errorref"></a>

## ErrorRef

```zig
pub const ErrorRef = errors.ErrorRef;
```

References: [`errors.ErrorRef`](api/errors.md#type-errorref)

<a id="alias-state"></a>

## State

```zig
pub const State = state.State;
```

References: [`state.State`](api/state.md#type-state)

<a id="alias-hostdata"></a>

## HostData

```zig
pub const HostData = state.HostData;
```

References: [`state.HostData`](api/state.md#type-hostdata)

<a id="alias-interrupthandle"></a>

## InterruptHandle

```zig
pub const InterruptHandle = state.InterruptHandle;
```

References: [`state.InterruptHandle`](api/state.md#type-interrupthandle)

<a id="alias-snapshot"></a>

## Snapshot

```zig
pub const Snapshot = snapshot.Snapshot;
```

References: [`snapshot.Snapshot`](api/snapshot.md#type-snapshot)

<a id="alias-libraryset"></a>

## LibrarySet

```zig
pub const LibrarySet = options.LibrarySet;
```

References: [`options.LibrarySet`](api/options.md#alias-libraryset)

<a id="alias-stdlib"></a>

## Stdlib

```zig
pub const Stdlib = options.Stdlib;
```

References: [`options.Stdlib`](api/options.md#type-stdlib)

<a id="alias-limits"></a>

## Limits

```zig
pub const Limits = options.Limits;
```

References: [`options.Limits`](api/options.md#type-limits)

<a id="alias-calloptions"></a>

## CallOptions

```zig
pub const CallOptions = options.CallOptions;
```

References: [`options.CallOptions`](api/options.md#type-calloptions)

<a id="alias-resumeoptions"></a>

## ResumeOptions

```zig
pub const ResumeOptions = options.ResumeOptions;
```

References: [`options.ResumeOptions`](api/options.md#type-resumeoptions)

<a id="alias-instructionbudget"></a>

## InstructionBudget

```zig
pub const InstructionBudget = options.InstructionBudget;
```

References: [`options.InstructionBudget`](api/options.md#type-instructionbudget)

<a id="alias-gcmode"></a>

## GcMode

```zig
pub const GcMode = options.GcMode;
```

References: [`options.GcMode`](api/options.md#alias-gcmode)

<a id="alias-gcparam"></a>

## GcParam

```zig
pub const GcParam = options.GcParam;
```

References: [`options.GcParam`](api/options.md#alias-gcparam)

<a id="alias-gcparams"></a>

## GcParams

```zig
pub const GcParams = options.GcParams;
```

References: [`options.GcParams`](api/options.md#alias-gcparams)

<a id="alias-gcoptions"></a>

## GcOptions

```zig
pub const GcOptions = options.GcOptions;
```

References: [`options.GcOptions`](api/options.md#type-gcoptions)

<a id="alias-debugoptions"></a>

## DebugOptions

```zig
pub const DebugOptions = options.DebugOptions;
```

References: [`options.DebugOptions`](api/options.md#type-debugoptions)

<a id="alias-options"></a>

## Options

```zig
pub const Options = options.Options;
```

References: [`options.Options`](api/options.md#type-options)

<a id="alias-loadmode"></a>

## LoadMode

```zig
pub const LoadMode = options.LoadMode;
```

References: [`options.LoadMode`](api/options.md#type-loadmode)

<a id="alias-loadoptions"></a>

## LoadOptions

```zig
pub const LoadOptions = options.LoadOptions;
```

References: [`options.LoadOptions`](api/options.md#type-loadoptions)

<a id="alias-bytecodeloadoptions"></a>

## BytecodeLoadOptions

```zig
pub const BytecodeLoadOptions = options.BytecodeLoadOptions;
```

References: [`options.BytecodeLoadOptions`](api/options.md#type-bytecodeloadoptions)

<a id="alias-bytecodedumpoptions"></a>

## BytecodeDumpOptions

```zig
pub const BytecodeDumpOptions = options.BytecodeDumpOptions;
```

References: [`options.BytecodeDumpOptions`](api/options.md#type-bytecodedumpoptions)

<a id="alias-tableoptions"></a>

## TableOptions

```zig
pub const TableOptions = options.TableOptions;
```

References: [`options.TableOptions`](api/options.md#type-tableoptions)

<a id="alias-gcstepresult"></a>

## GcStepResult

```zig
pub const GcStepResult = options.GcStepResult;
```

References: [`options.GcStepResult`](api/options.md#type-gcstepresult)

<a id="alias-memoryfile"></a>

## MemoryFile

```zig
pub const MemoryFile = capabilities.MemoryFile;
```

References: [`capabilities.MemoryFile`](api/capabilities.md#alias-memoryfile)

<a id="alias-memoryfilesystem"></a>

## MemoryFilesystem

```zig
pub const MemoryFilesystem = capabilities.MemoryFilesystem;
```

References: [`capabilities.MemoryFilesystem`](api/capabilities.md#alias-memoryfilesystem)

<a id="alias-outputflush"></a>

## OutputFlush

```zig
pub const OutputFlush = capabilities.OutputFlush;
```

References: [`capabilities.OutputFlush`](api/capabilities.md#alias-outputflush)

<a id="alias-iocapability"></a>

## IoCapability

```zig
pub const IoCapability = capabilities.IoCapability;
```

References: [`capabilities.IoCapability`](api/capabilities.md#type-iocapability)

<a id="alias-filesystemcapability"></a>

## FilesystemCapability

```zig
pub const FilesystemCapability = capabilities.FilesystemCapability;
```

References: [`capabilities.FilesystemCapability`](api/capabilities.md#alias-filesystemcapability)

<a id="alias-customfilesystem"></a>

## CustomFilesystem

```zig
pub const CustomFilesystem = capabilities.CustomFilesystem;
```

References: [`capabilities.CustomFilesystem`](api/capabilities.md#alias-customfilesystem)

<a id="alias-hostdirectory"></a>

## HostDirectory

```zig
pub const HostDirectory = capabilities.HostDirectory;
```

References: [`capabilities.HostDirectory`](api/capabilities.md#alias-hostdirectory)

<a id="alias-filesystemfilekind"></a>

## FilesystemFileKind

```zig
pub const FilesystemFileKind = capabilities.FilesystemFileKind;
```

References: [`capabilities.FilesystemFileKind`](api/capabilities.md#alias-filesystemfilekind)

<a id="alias-filesystemfilestat"></a>

## FilesystemFileStat

```zig
pub const FilesystemFileStat = capabilities.FilesystemFileStat;
```

References: [`capabilities.FilesystemFileStat`](api/capabilities.md#alias-filesystemfilestat)

<a id="alias-filesystemdirectoryentry"></a>

## FilesystemDirectoryEntry

```zig
pub const FilesystemDirectoryEntry = capabilities.FilesystemDirectoryEntry;
```

References: [`capabilities.FilesystemDirectoryEntry`](api/capabilities.md#alias-filesystemdirectoryentry)

<a id="alias-deinitfilesystemdirectoryentries"></a>

## deinitFilesystemDirectoryEntries

```zig
pub const deinitFilesystemDirectoryEntries = capabilities.deinitFilesystemDirectoryEntries;
```

References: [`capabilities.deinitFilesystemDirectoryEntries`](api/capabilities.md#alias-deinitfilesystemdirectoryentries)

<a id="alias-environmentcapability"></a>

## EnvironmentCapability

```zig
pub const EnvironmentCapability = capabilities.EnvironmentCapability;
```

References: [`capabilities.EnvironmentCapability`](api/capabilities.md#alias-environmentcapability)

<a id="alias-customenvironment"></a>

## CustomEnvironment

```zig
pub const CustomEnvironment = capabilities.CustomEnvironment;
```

References: [`capabilities.CustomEnvironment`](api/capabilities.md#alias-customenvironment)

<a id="alias-clockcapability"></a>

## ClockCapability

```zig
pub const ClockCapability = capabilities.ClockCapability;
```

References: [`capabilities.ClockCapability`](api/capabilities.md#alias-clockcapability)

<a id="alias-customclock"></a>

## CustomClock

```zig
pub const CustomClock = capabilities.CustomClock;
```

References: [`capabilities.CustomClock`](api/capabilities.md#alias-customclock)

<a id="alias-fixedclock"></a>

## FixedClock

```zig
pub const FixedClock = capabilities.FixedClock;
```

References: [`capabilities.FixedClock`](api/capabilities.md#alias-fixedclock)

<a id="alias-utcoffset"></a>

## UtcOffset

```zig
pub const UtcOffset = capabilities.UtcOffset;
```

References: [`capabilities.UtcOffset`](api/capabilities.md#alias-utcoffset)

<a id="alias-processcapability"></a>

## ProcessCapability

```zig
pub const ProcessCapability = capabilities.ProcessCapability;
```

References: [`capabilities.ProcessCapability`](api/capabilities.md#alias-processcapability)

<a id="alias-customprocess"></a>

## CustomProcess

```zig
pub const CustomProcess = capabilities.CustomProcess;
```

References: [`capabilities.CustomProcess`](api/capabilities.md#alias-customprocess)

<a id="alias-processresult"></a>

## ProcessResult

```zig
pub const ProcessResult = capabilities.ProcessResult;
```

References: [`capabilities.ProcessResult`](api/capabilities.md#alias-processresult)

<a id="alias-processstatus"></a>

## ProcessStatus

```zig
pub const ProcessStatus = capabilities.ProcessStatus;
```

References: [`capabilities.ProcessStatus`](api/capabilities.md#alias-processstatus)

<a id="alias-popenresult"></a>

## PopenResult

```zig
pub const PopenResult = capabilities.PopenResult;
```

References: [`capabilities.PopenResult`](api/capabilities.md#alias-popenresult)

<a id="alias-exitrequest"></a>

## ExitRequest

```zig
pub const ExitRequest = capabilities.ExitRequest;
```

References: [`capabilities.ExitRequest`](api/capabilities.md#alias-exitrequest)

<a id="alias-warninghandler"></a>

## WarningHandler

```zig
pub const WarningHandler = capabilities.WarningHandler;
```

References: [`capabilities.WarningHandler`](api/capabilities.md#alias-warninghandler)

<a id="alias-capabilities"></a>

## Capabilities

```zig
pub const Capabilities = capabilities.Capabilities;
```

References: [`capabilities.Capabilities`](api/capabilities.md#type-capabilities)

<a id="alias-value"></a>

## Value

```zig
pub const Value = value.Value;
```

References: [`value.Value`](api/value.md#type-value)

<a id="import-deinit"></a>

## deinit

```zig
pub const deinit = @import("api/convert.zig").deinit;
```

<a id="alias-ref"></a>

## Ref

```zig
pub const Ref = handle.Ref;
```

References: [`handle.Ref`](api/handle.md#type-ref)

<a id="alias-string"></a>

## String

```zig
pub const String = string.String;
```

References: [`string.String`](api/string.md#type-string)

<a id="alias-handlescope"></a>

## HandleScope

```zig
pub const HandleScope = handle.HandleScope;
```

References: [`handle.HandleScope`](api/handle.md#type-handlescope)

<a id="alias-table"></a>

## Table

```zig
pub const Table = table.Table;
```

References: [`table.Table`](api/table.md#type-table)

<a id="alias-function"></a>

## Function

```zig
pub const Function = function.Function;
```

References: [`function.Function`](api/function.md#type-function)

<a id="alias-coroutine"></a>

## Coroutine

```zig
pub const Coroutine = coroutine.Coroutine;
```

References: [`coroutine.Coroutine`](api/coroutine.md#type-coroutine)

<a id="alias-coroutinestatus"></a>

## CoroutineStatus

```zig
pub const CoroutineStatus = coroutine.CoroutineStatus;
```

References: [`coroutine.CoroutineStatus`](api/coroutine.md#alias-coroutinestatus)

<a id="alias-resumeresult"></a>

## ResumeResult

```zig
pub const ResumeResult = coroutine.ResumeResult;
```

References: [`coroutine.ResumeResult`](api/coroutine.md#fn-resumeresult)

<a id="alias-userdata"></a>

## Userdata

```zig
pub const Userdata = userdata.Userdata;
```

References: [`userdata.Userdata`](api/userdata.md#fn-userdata)

<a id="alias-anyuserdata"></a>

## AnyUserdata

```zig
pub const AnyUserdata = userdata.AnyUserdata;
```

References: [`userdata.AnyUserdata`](api/userdata.md#type-anyuserdata)

<a id="alias-userdataoptions"></a>

## UserdataOptions

```zig
pub const UserdataOptions = userdata.UserdataOptions;
```

References: [`userdata.UserdataOptions`](api/userdata.md#fn-userdataoptions)

<a id="alias-userdatatype"></a>

## UserdataType

```zig
pub const UserdataType = userdata.UserdataType;
```

References: [`userdata.UserdataType`](api/userdata.md#type-userdatatype)

<a id="alias-userdatasnapshothooks"></a>

## UserdataSnapshotHooks

```zig
pub const UserdataSnapshotHooks = userdata.UserdataSnapshotHooks;
```

References: [`userdata.UserdataSnapshotHooks`](api/userdata.md#fn-userdatasnapshothooks)

<a id="alias-analysis"></a>

## Analysis

```zig
pub const Analysis = analysis.Analysis;
```

<a id="alias-globaluse"></a>

## GlobalUse

```zig
pub const GlobalUse = analysis.GlobalUse;
```

<a id="alias-analyze"></a>

## analyze

```zig
pub const analyze = analysis.analyze;
```

<a id="alias-decoder"></a>

## Decoder

```zig
pub const Decoder = decoding.Decoder;
```

<a id="alias-decodeerror"></a>

## DecodeError

```zig
pub const DecodeError = decoding.DecodeError;
```

<a id="alias-decodeoptions"></a>

## DecodeOptions

```zig
pub const DecodeOptions = decoding.DecodeOptions;
```

<a id="alias-diagnostic"></a>

## Diagnostic

```zig
pub const Diagnostic = decoding.Diagnostic;
```

<a id="alias-fieldoptions"></a>

## FieldOptions

```zig
pub const FieldOptions = decoding.FieldOptions;
```

<a id="alias-decode"></a>

## decode

```zig
pub const decode = decoding.decode;
```

<a id="alias-defaultvalue"></a>

## defaultValue

```zig
pub const defaultValue = decoding.defaultValue;
```

<a id="alias-fieldkeys"></a>

## fieldKeys

```zig
pub const fieldKeys = decoding.fieldKeys;
```

<a id="alias-fieldoptions"></a>

## fieldOptions

```zig
pub const fieldOptions = decoding.fieldOptions;
```

<a id="alias-hostfn"></a>

## HostFn

```zig
pub const HostFn = callbacks.HostFn;
```

References: [`callbacks.HostFn`](api/callbacks.md#const-hostfn)

<a id="alias-context"></a>

## Context

```zig
pub const Context = context.Context;
```

References: [`context.Context`](api/context.md#type-context)

<a id="alias-host"></a>

## Host

```zig
pub const Host = context.Host;
```

References: [`context.Host`](api/context.md#fn-host)

<a id="alias-caller"></a>

## Caller

```zig
pub const Caller = context.Caller;
```

References: [`context.Caller`](api/context.md#type-caller)

