# api.errors

## Navigation

- [API Index](../README.md)
- Parent: [api](../api.md)

<details>
<summary>All documents</summary>

- [root](../root.md)
- [api](../api.md)
- [api.analyze](../api/analyze.md)
- [compile](../compile.md)
- [errors](../errors.md)
- [frontend.source](../frontend/source.md)
- [frontend.token](../frontend/token.md)
- [frontend](../frontend.md)
- [frontend.diagnostic](../frontend/diagnostic.md)
- [frontend.lexer](../frontend/lexer.md)
- [stack_guard](../stack_guard.md)
- [frontend.ast](../frontend/ast.md)
- [frontend.parser](../frontend/parser.md)
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
- [runtime.budget](../runtime/budget.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.io](../runtime/io.md)
- [runtime.host](../runtime/host.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.table_index](../runtime/table_index.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.operators](../runtime/operators.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.load](../runtime/load.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
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
- [stdlib.data](../stdlib/data.md)
- [stdlib.datetime](../stdlib/datetime.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.object_pool](../runtime/object_pool.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [runtime.native_fn](../runtime/native_fn.md)
- [compile.compiler](../compile/compiler.md)
- [compile.fold](../compile/fold.md)
- [compile.disasm](../compile/disasm.md)
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
- [api.namespace](../api/namespace.md)
- [api.context](../api/context.md)
- [api.decode](../api/decode.md)
- [api.coroutine](../api/coroutine.md)
- [api.string](../api/string.md)
- [api.snapshot](../api/snapshot.md)
- [api.memory_limit](../api/memory_limit.md)
- [testing](../testing.md)
- [testing.clua](../testing/clua.md)
- [testing.bench_runner](../testing/bench_runner.md)
- [testing.bench.options](../testing/bench/options.md)
- [testing.bench.results](../testing/bench/results.md)
- [testing.bench.stats](../testing/bench/stats.md)
- [testing.bench.report](../testing/bench/report.md)
- [testing.bench.api](../testing/bench/api.md)
- [testing.bench.allocation](../testing/bench/allocation.md)
- [testing.bench.process](../testing/bench/process.md)
- [testing.bench.fixtures](../testing/bench/fixtures.md)
- [testing.bench.legacy_process](../testing/bench/legacy_process.md)
- [testing.bench.startup](../testing/bench/startup.md)
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
- [testing.format_suite](../testing/format_suite.md)
- [testing.official_suite](../testing/official_suite.md)
- [testing.sandbox_runner](../testing/sandbox_runner.md)
- [testing.generators](../testing/generators.md)

</details>

## Functions

- [refFromRuntime](#fn-reffromruntime)
- [captureLuaError](#fn-captureluaerror)
- [takeMemoryLimitExceeded](#fn-takememorylimitexceeded)
- [memoryLimitError](#fn-memorylimiterror)
- [writeErrorValue](#fn-writeerrorvalue)
- [setLastErrorValue](#fn-setlasterrorvalue)
- [clearLastError](#fn-clearlasterror)
- [lastErrorValue](#fn-lasterrorvalue)
- [clearLastErrorTraceback](#fn-clearlasterrortraceback)

## Types

- [Error](#type-error)
- [UnsupportedOption](#type-unsupportedoption)
- [ConversionError](#type-conversionerror)
- [ErrorRef](#type-errorref)

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
| [traceback](#fn-errorref-traceback) | `self: ErrorRef` | `?[]const u8` | Traceback when &#96;CallOptions.traceback&#96; or &#96;ResumeOptions.traceback&#96; was set, formatted like &#96;debug.traceback&#96;; valid until &#96;deinit&#96;. |
| [value](#fn-errorref-value) | `self: ErrorRef` | `!Value` |  |
| [writeMessage](#fn-errorref-writemessage) | `self: ErrorRef, writer: *std.Io.Writer` | `!void` | Writes the error value as the CLI reports it. |
| [format](#fn-errorref-format) | `self: ErrorRef, writer: *std.Io.Writer` | `std.Io.Writer.Error!void` | Writes the message for the &#96;{f}&#96; format specifier. |

<a id="fn-errorref-deinit"></a>

### ErrorRef.deinit

```zig
pub fn deinit(self: *ErrorRef) void
```

References: [`ErrorRef`](#type-errorref)

<a id="fn-errorref-traceback"></a>

### ErrorRef.traceback

Traceback when `CallOptions.traceback` or `ResumeOptions.traceback` was set, formatted
like `debug.traceback`; valid until `deinit`.

```zig
pub fn traceback(self: ErrorRef) ?[]const u8
```

References: [`ErrorRef`](#type-errorref)

<a id="fn-errorref-value"></a>

### ErrorRef.value

```zig
pub fn value(self: ErrorRef) !Value
```

References: [`ErrorRef`](#type-errorref)

<a id="fn-errorref-writemessage"></a>

### ErrorRef.writeMessage

Writes the error value as the CLI reports it.

```zig
pub fn writeMessage(self: ErrorRef, writer: *std.Io.Writer) !void
```

References: [`ErrorRef`](#type-errorref)

<a id="fn-errorref-format"></a>

### ErrorRef.format

Writes the message for the `{f}` format specifier.

```zig
pub fn format(self: ErrorRef, writer: *std.Io.Writer) std.Io.Writer.Error!void
```

References: [`ErrorRef`](#type-errorref)

<a id="fn-reffromruntime"></a>

## refFromRuntime

```zig
pub fn refFromRuntime(state: *State, raw: runtime.Value) !ErrorRef
```

References: [`runtime.Value`](../runtime.md#alias-value), [`ErrorRef`](#type-errorref)

<a id="fn-captureluaerror"></a>

## captureLuaError

```zig
pub fn captureLuaError(state: *State, err: anyerror) anyerror
```

<a id="fn-takememorylimitexceeded"></a>

## takeMemoryLimitExceeded

```zig
pub fn takeMemoryLimitExceeded(state: *State) bool
```

<a id="fn-memorylimiterror"></a>

## memoryLimitError

Records the memory limit failure as the last Lua error and returns `error.LuaError`.

```zig
pub fn memoryLimitError(state: *State) error{LuaError}
```

<a id="fn-writeerrorvalue"></a>

## writeErrorValue

```zig
pub fn writeErrorValue(state: *State, value: runtime.Value, writer: *std.Io.Writer) !void
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-setlasterrorvalue"></a>

## setLastErrorValue

```zig
pub fn setLastErrorValue(state: *State, value: runtime.Value) !void
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-clearlasterror"></a>

## clearLastError

```zig
pub fn clearLastError(state: *State) void
```

<a id="fn-lasterrorvalue"></a>

## lastErrorValue

```zig
pub fn lastErrorValue(state: *State) runtime.Value
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-clearlasterrortraceback"></a>

## clearLastErrorTraceback

```zig
pub fn clearLastErrorTraceback(state: *State) void
```

