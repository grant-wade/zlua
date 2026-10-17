# api.options

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

## Functions

- [validateGcParam](#fn-validategcparam)
- [runtimeOptions](#fn-runtimeoptions)
- [toRuntimeStdlib](#fn-toruntimestdlib)

## Types

- [Stdlib](#type-stdlib)
- [Limits](#type-limits)
- [CallOptions](#type-calloptions)
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

## Aliases

- [LibrarySet](#alias-libraryset)
- [GcMode](#alias-gcmode)
- [GcParam](#alias-gcparam)
- [GcParams](#alias-gcparams)
- [DoOptions](#alias-dooptions)

<a id="alias-libraryset"></a>

## LibrarySet

```zig
pub const LibrarySet = stdlib.LibrarySet;
```

References: [`stdlib.LibrarySet`](../stdlib.md#type-libraryset)

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

<a id="fn-validategcparam"></a>

## validateGcParam

```zig
pub fn validateGcParam(value: i64) !void
```

<a id="fn-runtimeoptions"></a>

## runtimeOptions

```zig
pub fn runtimeOptions(options: Options) runtime.StateOptions
```

References: [`Options`](#type-options), [`runtime.StateOptions`](../runtime.md#alias-stateoptions)

<a id="fn-toruntimestdlib"></a>

## toRuntimeStdlib

```zig
pub fn toRuntimeStdlib(selection: Stdlib) runtime.StdlibMode
```

References: [`Stdlib`](#type-stdlib), [`runtime.StdlibMode`](../runtime.md#alias-stdlibmode)

