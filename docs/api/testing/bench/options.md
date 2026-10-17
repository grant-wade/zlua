# testing.bench.options

## Navigation

- [API Index](../../README.md)

<details>
<summary>All documents</summary>

- [root](../../root.md)
- [frontend](../../frontend.md)
- [errors](../../errors.md)
- [frontend.source](../../frontend/source.md)
- [frontend.token](../../frontend/token.md)
- [frontend.diagnostic](../../frontend/diagnostic.md)
- [frontend.lexer](../../frontend/lexer.md)
- [frontend.ast](../../frontend/ast.md)
- [frontend.parser](../../frontend/parser.md)
- [compile](../../compile.md)
- [compile.resolver](../../compile/resolver.md)
- [compile.bytecode](../../compile/bytecode.md)
- [compile.proto](../../compile/proto.md)
- [runtime.types](../../runtime/types.md)
- [runtime](../../runtime.md)
- [runtime.chunk](../../runtime/chunk.md)
- [reflection](../../reflection.md)
- [runtime.state](../../runtime/state.md)
- [stdlib](../../stdlib.md)
- [stdlib.base](../../stdlib/base.md)
- [runtime.call](../../runtime/call.md)
- [runtime.coroutine](../../runtime/coroutine.md)
- [runtime.debug](../../runtime/debug.md)
- [runtime.metatable](../../runtime/metatable.md)
- [runtime.rollback](../../runtime/rollback.md)
- [runtime.value](../../runtime/value.md)
- [runtime.number_format](../../runtime/number_format.md)
- [runtime.table_index](../../runtime/table_index.md)
- [runtime.host](../../runtime/host.md)
- [runtime.upvalue](../../runtime/upvalue.md)
- [runtime.failure](../../runtime/failure.md)
- [runtime.io](../../runtime/io.md)
- [runtime.load](../../runtime/load.md)
- [runtime.vm](../../runtime/vm.md)
- [runtime.gc](../../runtime/gc.md)
- [runtime.entry](../../runtime/entry.md)
- [runtime.system](../../runtime/system.md)
- [runtime.timezone](../../runtime/timezone.md)
- [runtime.index](../../runtime/index.md)
- [runtime.operators](../../runtime/operators.md)
- [stdlib.table](../../stdlib/table.md)
- [stdlib.string](../../stdlib/string.md)
- [stdlib.string.format](../../stdlib/string/format.md)
- [stdlib.string.pack](../../stdlib/string/pack.md)
- [stdlib.string.pattern](../../stdlib/string/pattern.md)
- [stdlib.math](../../stdlib/math.md)
- [stdlib.utf8](../../stdlib/utf8.md)
- [stdlib.coroutine](../../stdlib/coroutine.md)
- [stdlib.debug](../../stdlib/debug.md)
- [stdlib.io](../../stdlib/io.md)
- [stdlib.static_strings](../../stdlib/static_strings.md)
- [stdlib.os](../../stdlib/os.md)
- [stdlib.package](../../stdlib/package.md)
- [stdlib.json](../../stdlib/json.md)
- [stdlib.zerde_lua](../../stdlib/zerde_lua.md)
- [stdlib.toml](../../stdlib/toml.md)
- [stdlib.msgpack](../../stdlib/msgpack.md)
- [stdlib.csv](../../stdlib/csv.md)
- [stdlib.fs](../../stdlib/fs.md)
- [runtime.budget](../../runtime/budget.md)
- [runtime.strings](../../runtime/strings.md)
- [runtime.execute](../../runtime/execute.md)
- [testing.process](../../testing/process.md)
- [runtime.tests](../../runtime/tests.md)
- [runtime.internal](../../runtime/internal.md)
- [runtime.native_fn](../../runtime/native_fn.md)
- [runtime.address_index](../../runtime/address_index.md)
- [compile.compiler](../../compile/compiler.md)
- [compile.fold](../../compile/fold.md)
- [compile.disasm](../../compile/disasm.md)
- [api](../../api.md)
- [api.callbacks](../../api/callbacks.md)
- [api.convert](../../api/convert.md)
- [api.errors](../../api/errors.md)
- [api.handle](../../api/handle.md)
- [api.state](../../api/state.md)
- [runtime.snapshot](../../runtime/snapshot.md)
- [api.capabilities](../../api/capabilities.md)
- [api.options](../../api/options.md)
- [api.function](../../api/function.md)
- [api.table](../../api/table.md)
- [api.value](../../api/value.md)
- [api.userdata](../../api/userdata.md)
- [api.context](../../api/context.md)
- [api.coroutine](../../api/coroutine.md)
- [api.snapshot](../../api/snapshot.md)
- [api.memory_limit](../../api/memory_limit.md)
- [testing](../../testing.md)
- [testing.clua](../../testing/clua.md)
- [testing.bench_runner](../../testing/bench_runner.md)
- [testing.bench.options](../../testing/bench/options.md)
- [testing.bench.results](../../testing/bench/results.md)
- [testing.bench.stats](../../testing/bench/stats.md)
- [testing.bench.report](../../testing/bench/report.md)
- [testing.bench.process](../../testing/bench/process.md)
- [testing.bench.fixtures](../../testing/bench/fixtures.md)
- [testing.bench.legacy_process](../../testing/bench/legacy_process.md)
- [testing.bench.startup](../../testing/bench/startup.md)
- [testing.bench.allocation](../../testing/bench/allocation.md)
- [testing.bench.c_startup](../../testing/bench/c_startup.md)
- [testing.bench.snapshots](../../testing/bench/snapshots.md)
- [testing.bench.gc](../../testing/bench/gc.md)
- [testing.diff_runner](../../testing/diff_runner.md)
- [testing.fixtures](../../testing/fixtures.md)
- [testing.expected_failures](../../testing/expected_failures.md)
- [testing.metadata](../../testing/metadata.md)
- [testing.normalizer](../../testing/normalizer.md)
- [testing.parallel](../../testing/parallel.md)
- [testing.extension_runner](../../testing/extension_runner.md)
- [testing.official_suite](../../testing/official_suite.md)

</details>

## Functions

- [parseArgs](#fn-parseargs)
- [parsePositiveUsize](#fn-parsepositiveusize)
- [parsePositiveU64](#fn-parsepositiveu64)

## Types

- [Family](#type-family)
- [Options](#type-options)

<a id="type-family"></a>

## Family

```zig
pub const Family = enum {
    process,
    startup,
    snapshots,
    gc,
    all,
};
```

<a id="type-options"></a>

## Options

```zig
pub const Options = struct {
    family: Family = .all,
    verbose: bool = false,
    zlua_build: ?[]const u8 = null,
    snapshot_build: ?[]const u8 = null,
    clua_build: ?[]const u8 = null,
    c_build: ?[]const u8 = null,
    clua_c: ?[]const u8 = null,
    bench_root: []const u8 = default_bench_root,
    selectors: []const []const u8 = &.{},
    clua: ?[]const u8 = null,
    zlua: ?[]const u8 = null,
    zlua_snapshot: ?[]const u8 = null,
    list: bool = false,
    iterations: ?usize = null,
    warmup: ?usize = null,
    timeout_ms: ?u64 = null,
    category: ?[]const u8 = null,
    json_path: ?[]const u8 = null,
    csv_path: ?[]const u8 = null,
    debug_errors: bool = false,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [matches](#fn-options-matches) | `self: Options, group: []const u8, engine: []const u8, name: []const u8` | `bool` |  |
| [deinit](#fn-options-deinit) | `self: Options, allocator: std.mem.Allocator` | `void` |  |

<a id="fn-options-matches"></a>

### Options.matches

```zig
pub fn matches(self: Options, group: []const u8, engine: []const u8, name: []const u8) bool
```

References: [`Options`](#type-options)

<a id="fn-options-deinit"></a>

### Options.deinit

```zig
pub fn deinit(self: Options, allocator: std.mem.Allocator) void
```

References: [`Options`](#type-options)

<a id="fn-parseargs"></a>

## parseArgs

```zig
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Options
```

References: [`Options`](#type-options)

<a id="fn-parsepositiveusize"></a>

## parsePositiveUsize

```zig
pub fn parsePositiveUsize(value: []const u8) !usize
```

<a id="fn-parsepositiveu64"></a>

## parsePositiveU64

```zig
pub fn parsePositiveU64(value: []const u8) !u64
```

