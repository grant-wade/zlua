# api.coroutine

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

- [ResumeResult](#fn-resumeresult)

## Types

- [Coroutine](#type-coroutine)

## Aliases

- [CoroutineStatus](#alias-coroutinestatus)

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

State-local token valid while rooted and until reset.

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

