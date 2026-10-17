# api.capabilities

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
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.state](../runtime/state.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.host](../runtime/host.md)
- [runtime.timezone](../runtime/timezone.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
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
- [runtime.vm](../runtime/vm.md)
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

## Types

- [IoCapability](#type-iocapability)
- [Capabilities](#type-capabilities)

## Aliases

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

<a id="alias-memoryfile"></a>

## MemoryFile

```zig
pub const MemoryFile = runtime.MemoryFile;
```

References: [`runtime.MemoryFile`](../runtime.md#alias-memoryfile)

<a id="alias-memoryfilesystem"></a>

## MemoryFilesystem

Writable in-memory filesystem.

```zig
pub const MemoryFilesystem = runtime.MemoryFilesystem;
```

References: [`runtime.MemoryFilesystem`](../runtime.md#alias-memoryfilesystem)

<a id="alias-outputflush"></a>

## OutputFlush

When Lua output writers are flushed beyond explicit flush points.

```zig
pub const OutputFlush = runtime.OutputFlush;
```

References: [`runtime.OutputFlush`](../runtime.md#alias-outputflush)

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

References: [`runtime.FilesystemCapability`](../runtime.md#alias-filesystemcapability)

<a id="alias-customfilesystem"></a>

## CustomFilesystem

```zig
pub const CustomFilesystem = runtime.CustomFilesystem;
```

References: [`runtime.CustomFilesystem`](../runtime.md#alias-customfilesystem)

<a id="alias-hostdirectory"></a>

## HostDirectory

Borrowed directory root that scopes host filesystem access.

```zig
pub const HostDirectory = runtime.HostDirectory;
```

References: [`runtime.HostDirectory`](../runtime.md#alias-hostdirectory)

<a id="alias-filesystemfilekind"></a>

## FilesystemFileKind

```zig
pub const FilesystemFileKind = runtime.FilesystemFileKind;
```

References: [`runtime.FilesystemFileKind`](../runtime.md#alias-filesystemfilekind)

<a id="alias-filesystemfilestat"></a>

## FilesystemFileStat

```zig
pub const FilesystemFileStat = runtime.FilesystemFileStat;
```

References: [`runtime.FilesystemFileStat`](../runtime.md#alias-filesystemfilestat)

<a id="alias-filesystemdirectoryentry"></a>

## FilesystemDirectoryEntry

```zig
pub const FilesystemDirectoryEntry = runtime.FilesystemDirectoryEntry;
```

References: [`runtime.FilesystemDirectoryEntry`](../runtime.md#alias-filesystemdirectoryentry)

<a id="alias-deinitfilesystemdirectoryentries"></a>

## deinitFilesystemDirectoryEntries

```zig
pub const deinitFilesystemDirectoryEntries = runtime.deinitFilesystemDirectoryEntries;
```

References: [`runtime.deinitFilesystemDirectoryEntries`](../runtime.md#alias-deinitfilesystemdirectoryentries)

<a id="alias-environmentcapability"></a>

## EnvironmentCapability

Environment-variable access granted to `os.getenv` and enabled child processes.

```zig
pub const EnvironmentCapability = runtime.EnvironmentCapability;
```

References: [`runtime.EnvironmentCapability`](../runtime.md#alias-environmentcapability)

<a id="alias-customenvironment"></a>

## CustomEnvironment

```zig
pub const CustomEnvironment = runtime.CustomEnvironment;
```

References: [`runtime.CustomEnvironment`](../runtime.md#alias-customenvironment)

<a id="alias-clockcapability"></a>

## ClockCapability

Clock access granted to `os.time`, `os.date`, and `os.clock`.

```zig
pub const ClockCapability = runtime.ClockCapability;
```

References: [`runtime.ClockCapability`](../runtime.md#alias-clockcapability)

<a id="alias-customclock"></a>

## CustomClock

```zig
pub const CustomClock = runtime.CustomClock;
```

References: [`runtime.CustomClock`](../runtime.md#alias-customclock)

<a id="alias-fixedclock"></a>

## FixedClock

```zig
pub const FixedClock = runtime.FixedClock;
```

References: [`runtime.FixedClock`](../runtime.md#alias-fixedclock)

<a id="alias-utcoffset"></a>

## UtcOffset

```zig
pub const UtcOffset = runtime.UtcOffset;
```

References: [`runtime.UtcOffset`](../runtime.md#alias-utcoffset)

<a id="alias-processcapability"></a>

## ProcessCapability

Process access granted to `os.execute`, `io.popen`, and `os.exit`.

```zig
pub const ProcessCapability = runtime.ProcessCapability;
```

References: [`runtime.ProcessCapability`](../runtime.md#alias-processcapability)

<a id="alias-customprocess"></a>

## CustomProcess

```zig
pub const CustomProcess = runtime.CustomProcess;
```

References: [`runtime.CustomProcess`](../runtime.md#alias-customprocess)

<a id="alias-processresult"></a>

## ProcessResult

```zig
pub const ProcessResult = runtime.ProcessResult;
```

References: [`runtime.ProcessResult`](../runtime.md#alias-processresult)

<a id="alias-processstatus"></a>

## ProcessStatus

```zig
pub const ProcessStatus = runtime.ProcessStatus;
```

References: [`runtime.ProcessStatus`](../runtime.md#alias-processstatus)

<a id="alias-popenresult"></a>

## PopenResult

```zig
pub const PopenResult = runtime.PopenResult;
```

References: [`runtime.PopenResult`](../runtime.md#alias-popenresult)

<a id="alias-exitrequest"></a>

## ExitRequest

Exit code and close flag recorded by `os.exit`; see `State.exitRequest`.

```zig
pub const ExitRequest = runtime.ExitRequest;
```

References: [`runtime.ExitRequest`](../runtime.md#alias-exitrequest)

<a id="alias-warninghandler"></a>

## WarningHandler

```zig
pub const WarningHandler = runtime.WarningHandler;
```

References: [`runtime.WarningHandler`](../runtime.md#alias-warninghandler)

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

