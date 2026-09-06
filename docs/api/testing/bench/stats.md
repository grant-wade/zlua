# testing.bench.stats

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
- [testing.c_api_runner](../../testing/c_api_runner.md)
- [testing.fixtures](../../testing/fixtures.md)
- [testing.diff_runner](../../testing/diff_runner.md)
- [testing.expected_failures](../../testing/expected_failures.md)
- [testing.metadata](../../testing/metadata.md)
- [testing.normalizer](../../testing/normalizer.md)
- [testing.extension_runner](../../testing/extension_runner.md)
- [testing.official_suite](../../testing/official_suite.md)

</details>

## Functions

- [medianSortedNs](#fn-mediansortedns)
- [calculate](#fn-calculate)
- [ratio](#fn-ratio)
- [breakEven](#fn-breakeven)

## Types

- [TimingStats](#type-timingstats)

<a id="type-timingstats"></a>

## TimingStats

```zig
pub const TimingStats = struct {
    min_ns: u64 = 0,
    median_ns: u64 = 0,
    p95_ns: u64 = 0,
    mean_ns: u64 = 0,
    max_ns: u64 = 0,
    stddev_ns: u64 = 0,
};
```

<a id="fn-mediansortedns"></a>

## medianSortedNs

```zig
pub fn medianSortedNs(sorted: []const u64) u64
```

<a id="fn-calculate"></a>

## calculate

```zig
pub fn calculate(allocator: std.mem.Allocator, samples: []const u64) !TimingStats
```

References: [`TimingStats`](#type-timingstats)

<a id="fn-ratio"></a>

## ratio

```zig
pub fn ratio(numerator: u64, denominator: u64) ?f64
```

<a id="fn-breakeven"></a>

## breakEven

```zig
pub fn breakEven(capture: u64, reset: u64, rebuild: u64) ?u64
```

