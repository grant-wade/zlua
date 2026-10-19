# runtime.strings

## Navigation

- [API Index](../README.md)
- Parent: [runtime](../runtime.md)

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

- [destroy](#fn-destroy)

## Types

- [InternSet](#type-internset)
- [Strings](#type-strings)
- [Builder](#type-builder)

## Aliases

- [short_string_limit](#alias-short_string_limit)

<a id="alias-short_string_limit"></a>

## short_string_limit

Longer strings are allocated without interning, as in Lua.

```zig
pub const short_string_limit = String.short_limit;
```

<a id="type-internset"></a>

## InternSet

Open-addressed set of interned strings, seeded with the static catalog.

```zig
pub const InternSet = struct {
    hashes: []u32 = &.{},
    entries: []?*const String = &.{},
    count: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [initStatic](#fn-internset-initstatic) | `allocator: std.mem.Allocator, extra: usize` | `!InternSet` | &#96;extra&#96; is the number of strings to reserve beyond the static catalog. |
| [deinit](#fn-internset-deinit) | `self: *InternSet, allocator: std.mem.Allocator` | `void` |  |
| [clone](#fn-internset-clone) | `self: *const InternSet, allocator: std.mem.Allocator` | `!InternSet` |  |
| [find](#fn-internset-find) | `self: *const InternSet, bytes: []const u8, hash: u32` | `?*const String` |  |
| [ensureUnusedCapacity](#fn-internset-ensureunusedcapacity) | `self: *InternSet, allocator: std.mem.Allocator, extra: usize` | `!void` |  |
| [insertAssumeCapacity](#fn-internset-insertassumecapacity) | `self: *InternSet, string: *const String` | `void` | The string must be absent and capacity reserved. |
| [remove](#fn-internset-remove) | `self: *InternSet, string: *const String` | `void` |  |

<a id="fn-internset-initstatic"></a>

### InternSet.initStatic

`extra` is the number of strings to reserve beyond the static catalog.

```zig
pub fn initStatic(allocator: std.mem.Allocator, extra: usize) !InternSet
```

References: [`InternSet`](#type-internset)

<a id="fn-internset-deinit"></a>

### InternSet.deinit

```zig
pub fn deinit(self: *InternSet, allocator: std.mem.Allocator) void
```

References: [`InternSet`](#type-internset)

<a id="fn-internset-clone"></a>

### InternSet.clone

```zig
pub fn clone(self: *const InternSet, allocator: std.mem.Allocator) !InternSet
```

References: [`InternSet`](#type-internset)

<a id="fn-internset-find"></a>

### InternSet.find

```zig
pub inline fn find(self: *const InternSet, bytes: []const u8, hash: u32) ?*const String
```

References: [`InternSet`](#type-internset)

<a id="fn-internset-ensureunusedcapacity"></a>

### InternSet.ensureUnusedCapacity

```zig
pub fn ensureUnusedCapacity(self: *InternSet, allocator: std.mem.Allocator, extra: usize) !void
```

References: [`InternSet`](#type-internset)

<a id="fn-internset-insertassumecapacity"></a>

### InternSet.insertAssumeCapacity

The string must be absent and capacity reserved.

```zig
pub fn insertAssumeCapacity(self: *InternSet, string: *const String) void
```

References: [`InternSet`](#type-internset)

<a id="fn-internset-remove"></a>

### InternSet.remove

```zig
pub fn remove(self: *InternSet, string: *const String) void
```

References: [`InternSet`](#type-internset)

<a id="type-strings"></a>

## Strings

String interning. The set holds strings weakly; the collector removes entries it frees.

```zig
pub const Strings = struct {
    set: InternSet = .{},
    /// `Builder` storage, empty while a builder holds it.
    scratch: std.ArrayList(u8) = .empty,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-strings-deinit) | `strings: *Strings, allocator: std.mem.Allocator` | `void` |  |
| [intern](#fn-strings-intern) | `strings: *Strings, bytes: []const u8` | `!*const String` |  |
| [internConstant](#fn-strings-internconstant) | `strings: *Strings, bytes: []const u8` | `!*const String` | Interns at any length: identical literals share one string, as with Lua's parser. |
| [allocate](#fn-strings-allocate) | `strings: *Strings, bytes: []const u8` | `!*const String` | Copies &#96;bytes&#96; into a new collectable string without interning it. |
| [createLong](#fn-strings-createlong) | `strings: *Strings, len: usize` | `!*String` |  |
| [concat](#fn-strings-concat) | `strings: *Strings, left: []const u8, right: []const u8` | `!*const String` |  |
| [duplicate](#fn-strings-duplicate) | `strings: *Strings, source: *const String` | `!*const String` |  |
| [builder](#fn-strings-builder) | `strings: *Strings` | `Builder` |  |

<a id="fn-strings-deinit"></a>

### Strings.deinit

```zig
pub fn deinit(strings: *Strings, allocator: std.mem.Allocator) void
```

References: [`Strings`](#type-strings)

<a id="fn-strings-intern"></a>

### Strings.intern

```zig
pub fn intern(strings: *Strings, bytes: []const u8) !*const String
```

References: [`Strings`](#type-strings)

<a id="fn-strings-internconstant"></a>

### Strings.internConstant

Interns at any length: identical literals share one string, as with Lua's parser.

```zig
pub fn internConstant(strings: *Strings, bytes: []const u8) !*const String
```

References: [`Strings`](#type-strings)

<a id="fn-strings-allocate"></a>

### Strings.allocate

Copies `bytes` into a new collectable string without interning it.

```zig
pub fn allocate(strings: *Strings, bytes: []const u8) !*const String
```

References: [`Strings`](#type-strings)

<a id="fn-strings-createlong"></a>

### Strings.createLong

```zig
pub fn createLong(strings: *Strings, len: usize) !*String
```

References: [`Strings`](#type-strings)

<a id="fn-strings-concat"></a>

### Strings.concat

```zig
pub fn concat(strings: *Strings, left: []const u8, right: []const u8) !*const String
```

References: [`Strings`](#type-strings)

<a id="fn-strings-duplicate"></a>

### Strings.duplicate

```zig
pub fn duplicate(strings: *Strings, source: *const String) !*const String
```

References: [`Strings`](#type-strings)

<a id="fn-strings-builder"></a>

### Strings.builder

```zig
pub fn builder(strings: *Strings) Builder
```

References: [`Strings`](#type-strings), [`Builder`](#type-builder)

<a id="fn-destroy"></a>

## destroy

```zig
pub fn destroy(allocator: std.mem.Allocator, string: *const String) void
```

<a id="type-builder"></a>

## Builder

Accumulates bytes for one new string, like `luaL_Buffer`.

```zig
pub const Builder = struct {
    strings: *Strings,
    buffer: std.ArrayList(u8),
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-builder-deinit) | `self: *Builder` | `void` |  |
| [allocator](#fn-builder-allocator) | `self: *const Builder` | `std.mem.Allocator` |  |
| [append](#fn-builder-append) | `self: *Builder, byte: u8` | `!void` |  |
| [appendSlice](#fn-builder-appendslice) | `self: *Builder, bytes: []const u8` | `!void` |  |
| [appendNTimes](#fn-builder-appendntimes) | `self: *Builder, byte: u8, count: usize` | `!void` |  |
| [print](#fn-builder-print) | `self: *Builder, comptime fmt: []const u8, args: anytype` | `!void` |  |
| [finish](#fn-builder-finish) | `self: *Builder` | `!*const String` |  |

<a id="fn-builder-deinit"></a>

### Builder.deinit

```zig
pub fn deinit(self: *Builder) void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-allocator"></a>

### Builder.allocator

```zig
pub fn allocator(self: *const Builder) std.mem.Allocator
```

References: [`Builder`](#type-builder)

<a id="fn-builder-append"></a>

### Builder.append

```zig
pub fn append(self: *Builder, byte: u8) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-appendslice"></a>

### Builder.appendSlice

```zig
pub fn appendSlice(self: *Builder, bytes: []const u8) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-appendntimes"></a>

### Builder.appendNTimes

```zig
pub fn appendNTimes(self: *Builder, byte: u8, count: usize) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-print"></a>

### Builder.print

```zig
pub fn print(self: *Builder, comptime fmt: []const u8, args: anytype) !void
```

References: [`Builder`](#type-builder)

<a id="fn-builder-finish"></a>

### Builder.finish

```zig
pub fn finish(self: *Builder) !*const String
```

References: [`Builder`](#type-builder)

