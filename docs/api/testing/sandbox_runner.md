# testing.sandbox_runner

## Navigation

- [API Index](../README.md)
- Parent: [testing](../testing.md)

<details>
<summary>All documents</summary>

- [root](../root.md)
- [frontend](../frontend.md)
- [errors](../errors.md)
- [frontend.source](../frontend/source.md)
- [frontend.token](../frontend/token.md)
- [frontend.diagnostic](../frontend/diagnostic.md)
- [frontend.lexer](../frontend/lexer.md)
- [stack_guard](../stack_guard.md)
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
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
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
- [testing.sandbox_runner](../testing/sandbox_runner.md)
- [testing.generators](../testing/generators.md)

</details>

## Functions

- [parseMetadata](#fn-parsemetadata)
- [runChild](#fn-runchild)
- [generatePrograms](#fn-generateprograms)
- [runCli](#fn-runcli)

## Types

- [Metadata](#type-metadata)

<a id="type-metadata"></a>

## Metadata

Harness-owned limits a fixture may override in its leading `-- key: value` comments.

```zig
pub const Metadata = struct {
    outcome: Outcome = .ok,
    /// Substring required in the error message.
    message: []const u8 = "",
    stdlib: enum { safe, full } = .safe,
    max_memory: ?usize = 64 << 20,
    max_instructions: ?u64 = 1_000_000,
    call_instructions: ?u64 = null,
    max_output: usize = 16 << 20,
    interrupt_ms: ?u32 = null,
    /// Longest allowed gap between an interrupt request and the call returning.
    latency_ms: ?u32 = null,
    binary_chunks: bool = false,
    /// Fixtures that need more stack than this to reach the limit they test skip smaller stacks.
    min_stack: usize = 0,
    /// Also runs the fixture failing each allocation in turn and under collector stress.
    fault_sweep: bool = false,
};
```

<a id="fn-parsemetadata"></a>

## parseMetadata

```zig
pub fn parseMetadata(source: []const u8) !Metadata
```

References: [`Metadata`](#type-metadata)

<a id="fn-runchild"></a>

## runChild

Runs one fixture in this process and prints its results for the parent to check.

```zig
pub fn runChild(allocator: std.mem.Allocator, io: std.Io, path: []const u8, stack_bytes: usize) !void
```

<a id="fn-generateprograms"></a>

## generatePrograms

Writes `count` generated programs into `directory` for the differential harness.

```zig
pub fn generatePrograms(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, count: usize, seed: u64) !void
```

<a id="fn-runcli"></a>

## runCli

Runs every fixture on every stack size. `self_exe` is respawned with `--child`.

```zig
pub fn runCli(allocator: std.mem.Allocator, io: std.Io, self_exe: []const u8, args: []const []const u8) !u8
```

