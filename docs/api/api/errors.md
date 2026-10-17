# api.errors

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

- [CallResult](#fn-callresult)
- [refFromRuntime](#fn-reffromruntime)
- [captureLuaError](#fn-captureluaerror)
- [takeMemoryLimitExceeded](#fn-takememorylimitexceeded)
- [memoryLimitErrorRef](#fn-memorylimiterrorref)
- [setLastErrorValue](#fn-setlasterrorvalue)
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

References: [`ErrorRef`](#type-errorref)

<a id="fn-errorref-message"></a>

### ErrorRef.message

Formats the error value; the caller frees it with the state's allocator.

```zig
pub fn message(self: ErrorRef) ![]const u8
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

<a id="fn-memorylimiterrorref"></a>

## memoryLimitErrorRef

```zig
pub fn memoryLimitErrorRef(state: *State) !ErrorRef
```

References: [`ErrorRef`](#type-errorref)

<a id="fn-setlasterrorvalue"></a>

## setLastErrorValue

```zig
pub fn setLastErrorValue(state: *State, value: runtime.Value) !void
```

References: [`runtime.Value`](../runtime.md#alias-value)

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

