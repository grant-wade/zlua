# api.function

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
- [testing.bench.process](../testing/bench/process.md)
- [testing.bench.fixtures](../testing/bench/fixtures.md)
- [testing.bench.legacy_process](../testing/bench/legacy_process.md)
- [testing.bench.startup](../testing/bench/startup.md)
- [testing.bench.allocation](../testing/bench/allocation.md)
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

## Types

- [Function](#type-function)
- [CallBudget](#type-callbudget)

<a id="type-function"></a>

## Function

Rooted handle to any Lua function: a closure, host callback, or standard library function.

```zig
pub const Function = struct {
    ref: Ref,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-function-deinit) | `self: *Function` | `void` |  |
| [call](#fn-function-call) | `self: Function, args: anytype, comptime R: type` | `!R` | Converts the first result to &#96;R&#96;, or every result to a tuple &#96;R&#96;; Lua failures return &#96;error.LuaError&#96;, and &#96;State.takeError&#96; returns the error value. |
| [callWith](#fn-function-callwith) | `self: Function, args: anytype, comptime R: type, options: CallOptions` | `!R` |  |
| [dumpBytecode](#fn-function-dumpbytecode) | `self: Function, writer: *std.Io.Writer, options: BytecodeDumpOptions` | `!void` | Writes the function as a binary chunk; native callbacks return &#96;error.TypeMismatch&#96;. |

<a id="fn-function-deinit"></a>

### Function.deinit

```zig
pub fn deinit(self: *Function) void
```

References: [`Function`](#type-function)

<a id="fn-function-call"></a>

### Function.call

Converts the first result to `R`, or every result to a tuple `R`; Lua failures return
`error.LuaError`, and `State.takeError` returns the error value.

```zig
pub fn call(self: Function, args: anytype, comptime R: type) !R
```

References: [`Function`](#type-function)

<a id="fn-function-callwith"></a>

### Function.callWith

```zig
pub fn callWith(self: Function, args: anytype, comptime R: type, options: CallOptions) !R
```

References: [`Function`](#type-function)

<a id="fn-function-dumpbytecode"></a>

### Function.dumpBytecode

Writes the function as a binary chunk; native callbacks return `error.TypeMismatch`.

```zig
pub fn dumpBytecode(self: Function, writer: *std.Io.Writer, options: BytecodeDumpOptions) !void
```

References: [`Function`](#type-function)

<a id="type-callbudget"></a>

## CallBudget

```zig
pub const CallBudget = struct {
    active: bool,
    previous: ?u64,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [begin](#fn-callbudget-begin) | `state: *State, max_instructions: ?u64` | `CallBudget` |  |
| [end](#fn-callbudget-end) | `self: CallBudget, state: *State` | `void` |  |

<a id="fn-callbudget-begin"></a>

### CallBudget.begin

```zig
pub fn begin(state: *State, max_instructions: ?u64) CallBudget
```

References: [`CallBudget`](#type-callbudget)

<a id="fn-callbudget-end"></a>

### CallBudget.end

```zig
pub fn end(self: CallBudget, state: *State) void
```

References: [`CallBudget`](#type-callbudget)

