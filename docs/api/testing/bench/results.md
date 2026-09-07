# testing.bench.results

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
- [compile.compiler](../../compile/compiler.md)
- [compile.disasm](../../compile/disasm.md)
- [api](../../api.md)
- [runtime](../../runtime.md)
- [runtime.chunk](../../runtime/chunk.md)
- [runtime.types](../../runtime/types.md)
- [runtime.value](../../runtime/value.md)
- [runtime.execute](../../runtime/execute.md)
- [testing.process](../../testing/process.md)
- [runtime.state](../../runtime/state.md)
- [runtime.call](../../runtime/call.md)
- [runtime.coroutine](../../runtime/coroutine.md)
- [runtime.debug](../../runtime/debug.md)
- [runtime.gc](../../runtime/gc.md)
- [runtime.host](../../runtime/host.md)
- [stdlib](../../stdlib.md)
- [stdlib.base](../../stdlib/base.md)
- [stdlib.table](../../stdlib/table.md)
- [stdlib.string](../../stdlib/string.md)
- [stdlib.math](../../stdlib/math.md)
- [stdlib.utf8](../../stdlib/utf8.md)
- [stdlib.coroutine](../../stdlib/coroutine.md)
- [stdlib.debug](../../stdlib/debug.md)
- [stdlib.package](../../stdlib/package.md)
- [stdlib.io](../../stdlib/io.md)
- [stdlib.os](../../stdlib/os.md)
- [stdlib.json](../../stdlib/json.md)
- [stdlib.zerde_lua](../../stdlib/zerde_lua.md)
- [stdlib.toml](../../stdlib/toml.md)
- [stdlib.msgpack](../../stdlib/msgpack.md)
- [stdlib.csv](../../stdlib/csv.md)
- [stdlib.fs](../../stdlib/fs.md)
- [stdlib.static_strings](../../stdlib/static_strings.md)
- [runtime.vm](../../runtime/vm.md)
- [runtime.tests](../../runtime/tests.md)
- [runtime.internal](../../runtime/internal.md)
- [runtime.snapshot](../../runtime/snapshot.md)
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
- [testing.diff_runner](../../testing/diff_runner.md)
- [testing.fixtures](../../testing/fixtures.md)
- [testing.expected_failures](../../testing/expected_failures.md)
- [testing.metadata](../../testing/metadata.md)
- [testing.normalizer](../../testing/normalizer.md)
- [testing.extension_runner](../../testing/extension_runner.md)
- [testing.official_suite](../../testing/official_suite.md)

</details>

## Types

- [Metric](#type-metric)
- [MemoryScope](#type-memoryscope)
- [Status](#type-status)
- [BenchmarkResult](#type-benchmarkresult)
- [Case](#type-case)
- [Suite](#type-suite)

<a id="type-metric"></a>

## Metric

```zig
pub const Metric = struct {
    elapsed_ns: u64 = 0,
    allocations: ?u64 = null,
    resizes: ?u64 = null,
    requested_bytes: ?u64 = null,
    live_bytes: ?u64 = null,
    peak_bytes: ?u64 = null,
    runtime_bytes: ?u64 = null,
};
```

<a id="type-memoryscope"></a>

## MemoryScope

```zig
pub const MemoryScope = enum {
    unavailable,
    vm,
    checkpoint,
    new_state,
};
```

<a id="type-status"></a>

## Status

```zig
pub const Status = enum {
    benchmarked,
    skipped,
    failed,
    timed_out,
};
```

<a id="type-benchmarkresult"></a>

## BenchmarkResult

```zig
pub const BenchmarkResult = struct {
    group: []const u8,
    case: []const u8,
    engine: []const u8,
    operation: []const u8,
    category: []const u8 = "",
    build_mode: ?[]const u8 = null,
    executable: ?[]const u8 = null,
    failure_sample: ?usize = null,
    failure_during_warmup: bool = false,
    scope: []const u8,
    memory_scope: MemoryScope = .unavailable,
    iterations: usize,
    warmup: usize,
    timeout_ms: ?u64 = null,
    status: Status = .benchmarked,
    reason: []const u8 = "",
    samples: []const Metric = &.{},
    timing: ?stats.TimingStats = null,
};
```

<a id="type-case"></a>

## Case

```zig
pub const Case = struct {
    group: []const u8,
    engine: []const u8,
    name: []const u8,
    description: []const u8,
};
```

<a id="type-suite"></a>

## Suite

```zig
pub const Suite = struct {
    arena: std.heap.ArenaAllocator,
    results: std.ArrayList(BenchmarkResult) = .empty,
    cases: std.ArrayList(Case) = .empty,
    legacy_process: std.json.Value = .null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [init](#fn-suite-init) | `allocator: std.mem.Allocator` | `Suite` |  |
| [deinit](#fn-suite-deinit) | `self: *Suite` | `void` |  |
| [add](#fn-suite-add) | `self: *Suite, result: BenchmarkResult` | `!void` |  |
| [addCase](#fn-suite-addcase) | `self: *Suite, group: []const u8, engine: []const u8, name: []const u8, description: []const u8` | `!void` |  |
| [failed](#fn-suite-failed) | `self: *const Suite` | `bool` |  |

<a id="fn-suite-init"></a>

### Suite.init

```zig
pub fn init(allocator: std.mem.Allocator) Suite
```

References: [`Suite`](#type-suite)

<a id="fn-suite-deinit"></a>

### Suite.deinit

```zig
pub fn deinit(self: *Suite) void
```

References: [`Suite`](#type-suite)

<a id="fn-suite-add"></a>

### Suite.add

```zig
pub fn add(self: *Suite, result: BenchmarkResult) !void
```

References: [`Suite`](#type-suite), [`BenchmarkResult`](#type-benchmarkresult)

<a id="fn-suite-addcase"></a>

### Suite.addCase

```zig
pub fn addCase(self: *Suite, group: []const u8, engine: []const u8, name: []const u8, description: []const u8) !void
```

References: [`Suite`](#type-suite)

<a id="fn-suite-failed"></a>

### Suite.failed

```zig
pub fn failed(self: *const Suite) bool
```

References: [`Suite`](#type-suite)

