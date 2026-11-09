# api.convert

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

## Functions

- [expectedLuaType](#fn-expectedluatype)
- [convertArgs](#fn-convertargs)
- [toRuntimeValue](#fn-toruntimevalue)
- [toRuntimeValueNamed](#fn-toruntimevaluenamed)
- [canConvert](#fn-canconvert)
- [writeEntries](#fn-writeentries)
- [fromRuntimeResults](#fn-fromruntimeresults)
- [fromRuntimeValue](#fn-fromruntimevalue)
- [fromRuntimeBorrowed](#fn-fromruntimeborrowed)
- [integerFromFloat](#fn-integerfromfloat)
- [isOwnedApiValue](#fn-isownedapivalue)
- [deinit](#fn-deinit)
- [deinitIfOwned](#fn-deinitifowned)

## Types

- [TableSink](#type-tablesink)

<a id="fn-expectedluatype"></a>

## expectedLuaType

```zig
pub fn expectedLuaType(comptime T: type) []const u8
```

<a id="fn-convertargs"></a>

## convertArgs

```zig
pub fn convertArgs(state: *State, args: anytype) ![argCount(@TypeOf(args))]runtime.Value
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-toruntimevalue"></a>

## toRuntimeValue

```zig
pub fn toRuntimeValue(state: *State, value: anytype) !runtime.Value
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-toruntimevaluenamed"></a>

## toRuntimeValueNamed

Like `toRuntimeValue`; `name` labels a Zig function in Lua error messages.

```zig
pub fn toRuntimeValueNamed(state: *State, value: anytype, name: []const u8) !runtime.Value
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-canconvert"></a>

## canConvert

Whether `toRuntimeValue` accepts a `T`; pointers to structs are assumed convertible.

```zig
pub fn canConvert(comptime T: type) bool
```

<a id="type-tablesink"></a>

## TableSink

Receives entries for a fresh table.

```zig
pub const TableSink = struct {
    table: runtime.Value,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [put](#fn-tablesink-put) | `self: TableSink, state: *State, key: []const u8, value: runtime.Value` | `!void` |  |

<a id="fn-tablesink-put"></a>

### TableSink.put

```zig
pub fn put(self: TableSink, state: *State, key: []const u8, value: runtime.Value) !void
```

References: [`TableSink`](#type-tablesink), [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-writeentries"></a>

## writeEntries

Converts the fields of struct `value`, or the tags and exported declarations of struct or enum
type `value`, and passes each Lua key and value to `sink.put(state, key, value)`.

```zig
pub fn writeEntries(state: *State, sink: anytype, value: anytype) !void
```

<a id="fn-fromruntimeresults"></a>

## fromRuntimeResults

```zig
pub fn fromRuntimeResults(state: *State, results: []const runtime.Value, comptime R: type) !R
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-fromruntimevalue"></a>

## fromRuntimeValue

```zig
pub fn fromRuntimeValue(state: *State, raw: runtime.Value, comptime T: type) !T
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-fromruntimeborrowed"></a>

## fromRuntimeBorrowed

Like `fromRuntimeValue`, also reading `[]const u8` and `*T` that borrow VM memory. `raw` must
stay reachable while the result is used, as a callback argument does.

```zig
pub fn fromRuntimeBorrowed(state: *State, raw: runtime.Value, comptime T: type) !T
```

References: [`runtime.Value`](../runtime.md#alias-value)

<a id="fn-integerfromfloat"></a>

## integerFromFloat

```zig
pub fn integerFromFloat(value: f64) ?i64
```

<a id="fn-isownedapivalue"></a>

## isOwnedApiValue

```zig
pub fn isOwnedApiValue(comptime T: type) bool
```

<a id="fn-deinit"></a>

## deinit

Releases the handles in `value`, a pointer to a handle, `Value`, optional, or tuple.

```zig
pub fn deinit(value: anytype) void
```

<a id="fn-deinitifowned"></a>

## deinitIfOwned

```zig
pub fn deinitIfOwned(comptime T: type, value: *T) void
```

