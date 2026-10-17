# api.function

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

## Types

- [Function](#type-function)

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

References: [`Function`](#type-function)

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

References: [`Function`](#type-function)

<a id="fn-function-dumpbytecode"></a>

### Function.dumpBytecode

Native callbacks return `error.TypeMismatch`.
The caller frees the result with the state's allocator.

```zig
pub fn dumpBytecode(self: Function, options: BytecodeDumpOptions) ![]const u8
```

References: [`Function`](#type-function)

