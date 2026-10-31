# api.decode

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
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.table_index](../runtime/table_index.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.operators](../runtime/operators.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.io](../runtime/io.md)
- [runtime.host](../runtime/host.md)
- [runtime.load](../runtime/load.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.upvalue](../runtime/upvalue.md)
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
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.budget](../runtime/budget.md)
- [runtime.object_pool](../runtime/object_pool.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [runtime.native_fn](../runtime/native_fn.md)
- [compile.compiler](../compile/compiler.md)
- [compile.fold](../compile/fold.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
- [api.analyze](../api/analyze.md)
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
- [api.decode](../api/decode.md)
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
- [testing.bench.system](../testing/bench/system.md)
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

- [fieldOptions](#fn-fieldoptions)
- [fieldKeys](#fn-fieldkeys)
- [isEnumArray](#fn-isenumarray)
- [isEnumSet](#fn-isenumset)
- [hasFromLua](#fn-hasfromlua)
- [hasToLua](#fn-hastolua)
- [needsDecoding](#fn-needsdecoding)
- [defaultValue](#fn-defaultvalue)
- [Decoder](#fn-decoder)
- [decode](#fn-decode)

## Types

- [Diagnostic](#type-diagnostic)
- [FieldOptions](#type-fieldoptions)
- [DecodeOptions](#type-decodeoptions)

## Constants

- [DecodeError](#const-decodeerror)

<a id="const-decodeerror"></a>

## DecodeError

```zig
pub const DecodeError = error{Invalid} || Allocator.Error;
```

<a id="type-diagnostic"></a>

## Diagnostic

The message of the first decoding failure.

```zig
pub const Diagnostic = struct {
    gpa: Allocator,
    /// Owned by `gpa`; empty until something fails.
    text: []u8 = &.{},
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-diagnostic-deinit) | `self: *Diagnostic` | `void` |  |
| [fail](#fn-diagnostic-fail) | `self: *Diagnostic, comptime fmt: []const u8, args: anytype` | `DecodeError` | Records the message unless one is recorded already, and returns &#96;error.Invalid&#96;. |
| [take](#fn-diagnostic-take) | `self: *Diagnostic` | `[]u8` | The message, owned by &#96;gpa&#96;, leaving the diagnostic empty. |

<a id="fn-diagnostic-deinit"></a>

### Diagnostic.deinit

```zig
pub fn deinit(self: *Diagnostic) void
```

References: [`Diagnostic`](#type-diagnostic)

<a id="fn-diagnostic-fail"></a>

### Diagnostic.fail

Records the message unless one is recorded already, and returns `error.Invalid`.

```zig
pub fn fail(self: *Diagnostic, comptime fmt: []const u8, args: anytype) DecodeError
```

References: [`Diagnostic`](#type-diagnostic), [`DecodeError`](#const-decodeerror)

<a id="fn-diagnostic-take"></a>

### Diagnostic.take

The message, owned by `gpa`, leaving the diagnostic empty.

```zig
pub fn take(self: *Diagnostic) []u8
```

References: [`Diagnostic`](#type-diagnostic)

<a id="type-fieldoptions"></a>

## FieldOptions

How a struct field maps to a Lua table, from the struct's `lua` declaration.

```zig
pub const FieldOptions = struct {
    /// The Lua key, the field name by default.
    key: []const u8,
    /// Decoding fails when the key is absent.
    required: bool = false,
    /// A description for generated documentation.
    doc: []const u8 = "",
    /// The fields of this struct field are given inline in the outer table.
    embed: bool = false,
    /// The enum whose values a bit set field lists; each sets the bit of its integer value.
    elements: ?type = null,
};
```

<a id="fn-fieldoptions"></a>

## fieldOptions

The options of field `name` of `T`.

```zig
pub fn fieldOptions(comptime T: type, comptime name: []const u8) FieldOptions
```

References: [`FieldOptions`](#type-fieldoptions)

<a id="fn-fieldkeys"></a>

## fieldKeys

The Lua keys of the fields of `T`, with the fields of embedded structs in place of their own.

```zig
pub fn fieldKeys(comptime T: type) [keyCount(T)][]const u8
```

<a id="fn-isenumarray"></a>

## isEnumArray

```zig
pub fn isEnumArray(comptime T: type) bool
```

<a id="fn-isenumset"></a>

## isEnumSet

```zig
pub fn isEnumSet(comptime T: type) bool
```

<a id="fn-hasfromlua"></a>

## hasFromLua

```zig
pub fn hasFromLua(comptime T: type) bool
```

<a id="fn-hastolua"></a>

## hasToLua

```zig
pub fn hasToLua(comptime T: type) bool
```

<a id="fn-needsdecoding"></a>

## needsDecoding

Whether a typed callback parameter of type `T` is read by `Context.decodeArg`.

```zig
pub fn needsDecoding(comptime T: type) bool
```

<a id="fn-defaultvalue"></a>

## defaultValue

The value a field of type `T` holds before decoding: struct defaults, otherwise zeros and empties.

```zig
pub fn defaultValue(comptime T: type) T
```

<a id="fn-decoder"></a>

## Decoder

Reads Lua values into Zig values by their types, reporting the first failure with its path.

A type may declare `pub fn fromLua(d: anytype, value: Value, out: *T) DecodeError!void`.
`Context` may decide types it does not own with `pub fn decodes(comptime T: type) bool` and
`pub fn decode(d: anytype, comptime T: type, value: Value, out: *T) DecodeError!void`; it is
reachable as `d.context`.

```zig
pub fn Decoder(comptime Context: type) type
```

<a id="type-decodeoptions"></a>

## DecodeOptions

Options for `decode`.

```zig
pub const DecodeOptions = struct {
    /// Allocates the decoded strings and slices; a failed decode does not free them.
    allocator: Allocator,
    /// Receives the message of `error.Invalid`.
    diagnostic: *Diagnostic,
    /// Levels below the value whose struct fields and enum array entries must all be given.
    strict: u32 = 0,
    ignore_enum_case: bool = false,
};
```

<a id="fn-decode"></a>

## decode

Decodes `value` into a `T`, starting from `defaultValue(T)`.

```zig
pub fn decode(comptime T: type, value: Value, options: DecodeOptions) DecodeError!T
```

References: [`DecodeOptions`](#type-decodeoptions), [`DecodeError`](#const-decodeerror)

