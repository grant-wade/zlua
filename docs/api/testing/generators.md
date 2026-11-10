# testing.generators

## Navigation

- [API Index](../README.md)
- Parent: [testing](../testing.md)

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

- [writeProgram](#fn-writeprogram)
- [writeLibraryCalls](#fn-writelibrarycalls)
- [writeFormatText](#fn-writeformattext)
- [appendChunk](#fn-appendchunk)

## Types

- [Picker](#type-picker)

<a id="type-picker"></a>

## Picker

Source of choices for generators, backed by a fuzzer or a seeded random stream.

```zig
pub const Picker = struct {
    context: *anyopaque,
    next: *const fn (*anyopaque, u32) u32,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [fromSmith](#fn-picker-fromsmith) | `smith: *std.testing.Smith` | `Picker` |  |
| [fromRandom](#fn-picker-fromrandom) | `random: *std.Random` | `Picker` |  |
| [below](#fn-picker-below) | `self: Picker, limit: u32` | `u32` | A value below &#96;limit&#96;, which must not be zero. |
| [chance](#fn-picker-chance) | `self: Picker, percent: u32` | `bool` |  |
| [pick](#fn-picker-pick) | `self: Picker, comptime T: type, items: []const T` | `T` |  |

<a id="fn-picker-fromsmith"></a>

### Picker.fromSmith

```zig
pub fn fromSmith(smith: *std.testing.Smith) Picker
```

References: [`Picker`](#type-picker)

<a id="fn-picker-fromrandom"></a>

### Picker.fromRandom

```zig
pub fn fromRandom(random: *std.Random) Picker
```

References: [`Picker`](#type-picker)

<a id="fn-picker-below"></a>

### Picker.below

A value below `limit`, which must not be zero.

```zig
pub fn below(self: Picker, limit: u32) u32
```

References: [`Picker`](#type-picker)

<a id="fn-picker-chance"></a>

### Picker.chance

```zig
pub fn chance(self: Picker, percent: u32) bool
```

References: [`Picker`](#type-picker)

<a id="fn-picker-pick"></a>

### Picker.pick

```zig
pub fn pick(self: Picker, comptime T: type, items: []const T) T
```

References: [`Picker`](#type-picker)

<a id="fn-writeprogram"></a>

## writeProgram

Writes a Lua program whose output depends only on Lua semantics.

```zig
pub fn writeProgram(picker: Picker, out: *std.Io.Writer) !void
```

References: [`Picker`](#type-picker)

<a id="fn-writelibrarycalls"></a>

## writeLibraryCalls

Writes a chunk that calls standard library functions with hostile arguments.

```zig
pub fn writeLibraryCalls(picker: Picker, out: *std.Io.Writer) !void
```

References: [`Picker`](#type-picker)

<a id="fn-writeformattext"></a>

## writeFormatText

Writes text mixing the tokens of the data formats.

```zig
pub fn writeFormatText(picker: Picker, out: *std.Io.Writer) !void
```

References: [`Picker`](#type-picker)

<a id="fn-appendchunk"></a>

## appendChunk

Appends a binary chunk that passes verification, biased to run past its first instructions.

```zig
pub fn appendChunk(picker: Picker, allocator: Allocator, out: *std.ArrayList(u8)) !void
```

References: [`Picker`](#type-picker)

