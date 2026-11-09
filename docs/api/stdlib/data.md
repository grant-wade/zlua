# stdlib.data

## Navigation

- [API Index](../README.md)
- Parent: [stdlib](../stdlib.md)

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

- [ensureSupportTables](#fn-ensuresupporttables)
- [nullValue](#fn-nullvalue)
- [newExtension](#fn-newextension)
- [inputBytes](#fn-inputbytes)
- [optionsTable](#fn-optionstable)
- [enumOption](#fn-enumoption)
- [boolOption](#fn-booloption)
- [fail](#fn-fail)
- [failAtLine](#fn-failatline)
- [failAtByte](#fn-failatbyte)
- [writeFloat](#fn-writefloat)
- [returnEncoded](#fn-returnencoded)
- [returnValue](#fn-returnvalue)

## Types

- [Extension](#type-extension)
- [ByteText](#type-bytetext)
- [Builder](#type-builder)
- [Shape](#type-shape)
- [PathStep](#type-pathstep)
- [Walker](#type-walker)

## Constants

- [max_depth](#const-max_depth)

<a id="const-max_depth"></a>

## max_depth

```zig
pub const max_depth = 64;
```

<a id="fn-ensuresupporttables"></a>

## ensureSupportTables

```zig
pub fn ensureSupportTables(state: *State) !void
```

<a id="fn-nullvalue"></a>

## nullValue

```zig
pub fn nullValue(state: *State) !Value
```

<a id="type-extension"></a>

## Extension

A MessagePack extension value that is not a timestamp.

```zig
pub const Extension = struct {
    type_id: i8,
    data: []const u8,
};
```

<a id="fn-newextension"></a>

## newExtension

```zig
pub fn newExtension(state: *State, extension: Extension) !Value
```

References: [`Extension`](#type-extension)

<a id="fn-inputbytes"></a>

## inputBytes

```zig
pub fn inputBytes(state: *State, value: Value, function_name: []const u8) ![]const u8
```

<a id="fn-optionstable"></a>

## optionsTable

Returns the options table at argument 2, or null when it is absent or nil.

```zig
pub fn optionsTable(state: *State, thread: *Thread, op: bytecode.Call, operation: []const u8) !?*Table
```

<a id="fn-enumoption"></a>

## enumOption

Returns the string option `name` matched against `choices`, or null when it is unset.
Each choice maps its accepted spellings to a result.

```zig
pub fn enumOption(
    state: *State,
    table: *Table,
    operation: []const u8,
    comptime name: []const u8,
    comptime T: type,
    comptime choices: []const struct { []const []const u8, T },
    comptime invalid: []const u8,
) !?T
```

<a id="fn-booloption"></a>

## boolOption

```zig
pub fn boolOption(state: *State, table: *Table, operation: []const u8, comptime name: []const u8) !?bool
```

<a id="fn-fail"></a>

## fail

```zig
pub fn fail(state: *State, operation: []const u8, comptime fmt: []const u8, args: anytype) runtime.RuntimeError
```

References: [`runtime.RuntimeError`](../runtime.md#alias-runtimeerror)

<a id="fn-failatline"></a>

## failAtLine

Fails with the 1-based line and column of byte `offset` in `input`.

```zig
pub fn failAtLine(state: *State, operation: []const u8, input: []const u8, offset: usize, comptime fmt: []const u8, args: anytype) runtime.RuntimeError
```

References: [`runtime.RuntimeError`](../runtime.md#alias-runtimeerror)

<a id="fn-failatbyte"></a>

## failAtByte

```zig
pub fn failAtByte(state: *State, operation: []const u8, offset: usize, comptime fmt: []const u8, args: anytype) runtime.RuntimeError
```

References: [`runtime.RuntimeError`](../runtime.md#alias-runtimeerror)

<a id="type-bytetext"></a>

## ByteText

Formats one input byte for an error message.

```zig
pub const ByteText = struct {
    byte: u8,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [format](#fn-bytetext-format) | `self: ByteText, writer: *std.Io.Writer` | `std.Io.Writer.Error!void` |  |

<a id="fn-bytetext-format"></a>

### ByteText.format

```zig
pub fn format(self: ByteText, writer: *std.Io.Writer) std.Io.Writer.Error!void
```

References: [`ByteText`](#type-bytetext)

<a id="type-builder"></a>

## Builder

Builds Lua tables from a stream of decoded values.

```zig
pub const Builder = struct {
    state: *State,
    stack: std.ArrayList(Frame) = .empty,
    root: Value = .nil,
    has_root: bool = false,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Kind](#type-builder-kind) |  |  |  |
| [Frame](#type-builder-frame) |  |  |  |
| [init](#fn-builder-init) | `state: *State` | `Builder` |  |
| [deinit](#fn-builder-deinit) | `self: *Builder` | `void` |  |
| [depth](#fn-builder-depth) | `self: *const Builder` | `usize` |  |
| [top](#fn-builder-top) | `self: *Builder` | `*Frame` |  |
| [begin](#fn-builder-begin) | `self: *Builder, kind: Kind, hint: usize` | `!void` | &#96;hint&#96; is the expected number of entries. |
| [setKey](#fn-builder-setkey) | `self: *Builder, key: []const u8` | `!void` |  |
| [end](#fn-builder-end) | `self: *Builder` | `!void` |  |
| [append](#fn-builder-append) | `self: *Builder, value: Value` | `!void` |  |
| [appendString](#fn-builder-appendstring) | `self: *Builder, bytes: []const u8` | `!void` |  |
| [appendNull](#fn-builder-appendnull) | `self: *Builder` | `!void` |  |

<a id="type-builder-kind"></a>

### Builder.Kind

```zig
pub const Kind = enum {
    array,
    object,
};
```

<a id="type-builder-frame"></a>

### Builder.Frame

```zig
pub const Frame = struct {
    kind: Kind,
    table: *Table,
    next_index: i64 = 1,
    key: ?*const String = null,
    /// Values or key/value pairs still expected, for formats with counted containers.
    remaining: usize = 0,
};
```

<a id="fn-builder-init"></a>

### Builder.init

```zig
pub fn init(state: *State) Builder
```

References: [`Builder`](#type-builder)

<a id="fn-builder-deinit"></a>

### Builder.deinit

```zig
pub fn deinit(self: *Builder) void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-depth"></a>

### Builder.depth

```zig
pub fn depth(self: *const Builder) usize
```

References: [`Builder`](#type-builder)

<a id="fn-builder-top"></a>

### Builder.top

```zig
pub fn top(self: *Builder) *Frame
```

References: [`Builder`](#type-builder), [`Frame`](#type-builder-frame)

<a id="fn-builder-begin"></a>

### Builder.begin

`hint` is the expected number of entries.

```zig
pub fn begin(self: *Builder, kind: Kind, hint: usize) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-setkey"></a>

### Builder.setKey

```zig
pub fn setKey(self: *Builder, key: []const u8) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-end"></a>

### Builder.end

```zig
pub fn end(self: *Builder) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-append"></a>

### Builder.append

```zig
pub fn append(self: *Builder, value: Value) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-appendstring"></a>

### Builder.appendString

```zig
pub fn appendString(self: *Builder, bytes: []const u8) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-appendnull"></a>

### Builder.appendNull

```zig
pub fn appendNull(self: *Builder) !void
```

References: [`Builder`](#type-builder)

<a id="type-shape"></a>

## Shape

How a writer encodes a Lua table.

```zig
pub const Shape = union(enum) {
    null,
    array: usize,
    object: usize,
    datetime: datetime.DateTime,
    extension: Extension,
};
```

<a id="type-pathstep"></a>

## PathStep

One step from a table to the value being written, for error messages.

```zig
pub const PathStep = union(enum) {
    none,
    index: usize,
    key: []const u8,
};
```

<a id="type-walker"></a>

## Walker

Walks Lua values for a writer, rejecting cycles and deep nesting.

```zig
pub const Walker = struct {
    state: *State,
    operation: []const u8,
    tables: [max_depth]*Table = undefined,
    steps: [max_depth]PathStep = undefined,
    depth: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [init](#fn-walker-init) | `state: *State, operation: []const u8` | `Walker` |  |
| [visit](#fn-walker-visit) | `self: *Walker, value: Value` | `!void` | Call once per value written. |
| [isNull](#fn-walker-isnull) | `self: *Walker, table: *Table` | `bool` |  |
| [enter](#fn-walker-enter) | `self: *Walker, table: *Table` | `!Shape` | Classifies &#96;table&#96; and pushes it when it is an array or object. Pair each array or object result with &#96;leave&#96;. |
| [leave](#fn-walker-leave) | `self: *Walker` | `void` |  |
| [step](#fn-walker-step) | `self: *Walker, child: PathStep` | `void` | Records which child of the innermost open table is being written. |
| [classify](#fn-walker-classify) | `self: *Walker, table: *Table` | `!Shape` |  |
| [fail](#fn-walker-fail) | `self: *Walker, comptime fmt: []const u8, args: anytype` | `runtime.RuntimeError` |  |
| [failValue](#fn-walker-failvalue) | `self: *Walker, value: Value` | `runtime.RuntimeError` |  |

<a id="fn-walker-init"></a>

### Walker.init

```zig
pub fn init(state: *State, operation: []const u8) Walker
```

References: [`Walker`](#type-walker)

<a id="fn-walker-visit"></a>

### Walker.visit

[Call](../compile/bytecode.md#type-call) once per value written.

```zig
pub fn visit(self: *Walker, value: Value) !void
```

References: [`Walker`](#type-walker)

<a id="fn-walker-isnull"></a>

### Walker.isNull

```zig
pub fn isNull(self: *Walker, table: *Table) bool
```

References: [`Walker`](#type-walker)

<a id="fn-walker-enter"></a>

### Walker.enter

Classifies `table` and pushes it when it is an array or object. Pair each
array or object result with `leave`.

```zig
pub fn enter(self: *Walker, table: *Table) !Shape
```

References: [`Walker`](#type-walker), [`Shape`](#type-shape)

<a id="fn-walker-leave"></a>

### Walker.leave

```zig
pub fn leave(self: *Walker) void
```

References: [`Walker`](#type-walker)

<a id="fn-walker-step"></a>

### Walker.step

Records which child of the innermost open table is being written.

```zig
pub fn step(self: *Walker, child: PathStep) void
```

References: [`Walker`](#type-walker), [`PathStep`](#type-pathstep)

<a id="fn-walker-classify"></a>

### Walker.classify

```zig
pub fn classify(self: *Walker, table: *Table) !Shape
```

References: [`Walker`](#type-walker), [`Shape`](#type-shape)

<a id="fn-walker-fail"></a>

### Walker.fail

```zig
pub fn fail(self: *Walker, comptime fmt: []const u8, args: anytype) runtime.RuntimeError
```

References: [`Walker`](#type-walker), [`runtime.RuntimeError`](../runtime.md#alias-runtimeerror)

<a id="fn-walker-failvalue"></a>

### Walker.failValue

```zig
pub fn failValue(self: *Walker, value: Value) runtime.RuntimeError
```

References: [`Walker`](#type-walker), [`runtime.RuntimeError`](../runtime.md#alias-runtimeerror)

<a id="fn-writefloat"></a>

## writeFloat

`value` must be finite. The text always has a fraction or an exponent.

```zig
pub fn writeFloat(writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void
```

<a id="fn-returnencoded"></a>

## returnEncoded

Runs `encode(context, writer)` into a fresh buffer and returns the result as a Lua string.

```zig
pub fn returnEncoded(state: *State, thread: *Thread, op: bytecode.Call, operation: []const u8, context: anytype, comptime encode: anytype) (runtime.RuntimeError || error{Interrupted})!void
```

References: [`runtime.RuntimeError`](../runtime.md#alias-runtimeerror)

<a id="fn-returnvalue"></a>

## returnValue

```zig
pub fn returnValue(state: *State, thread: *Thread, op: bytecode.Call, value: Value) !void
```

