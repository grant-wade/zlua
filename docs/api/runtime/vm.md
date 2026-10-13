# runtime.vm

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
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.state](../runtime/state.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.host](../runtime/host.md)
- [runtime.timezone](../runtime/timezone.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [stdlib.table](../stdlib/table.md)
- [stdlib.string](../stdlib/string.md)
- [stdlib.math](../stdlib/math.md)
- [stdlib.utf8](../stdlib/utf8.md)
- [stdlib.coroutine](../stdlib/coroutine.md)
- [stdlib.debug](../stdlib/debug.md)
- [stdlib.io](../stdlib/io.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [compile.compiler](../compile/compiler.md)
- [compile.fold](../compile/fold.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
- [runtime.snapshot](../runtime/snapshot.md)
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
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Functions

- [checkExecutionLimits](#fn-checkexecutionlimits)
- [executionCheckpoint](#fn-executioncheckpoint)
- [checkInterrupt](#fn-checkinterrupt)
- [instructionBudgetExhausted](#fn-instructionbudgetexhausted)

## Types

- [InterruptControl](#type-interruptcontrol)

## Constants

- [interrupt_poll_interval](#const-interrupt_poll_interval)

<a id="const-interrupt_poll_interval"></a>

## interrupt_poll_interval

Main-loop instructions between interrupt polls once a state has an
interrupt control. The fast loop also polls at backward jumps and calls.

```zig
pub const interrupt_poll_interval: u64 = 1024;
```

<a id="type-interruptcontrol"></a>

## InterruptControl

Interrupt request shared between a state and host threads.

The state allocates it on first request and frees it in `deinit`, so its
address stays stable when the owning state value moves. Only `requested`
is touched from other threads.

```zig
pub const InterruptControl = struct {
    requested: std.atomic.Value(bool) = .init(false),
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [request](#fn-interruptcontrol-request) | `self: *InterruptControl` | `void` |  |
| [clear](#fn-interruptcontrol-clear) | `self: *InterruptControl` | `void` |  |
| [isRequested](#fn-interruptcontrol-isrequested) | `self: *const InterruptControl` | `bool` |  |

<a id="fn-interruptcontrol-request"></a>

### InterruptControl.request

```zig
pub fn request(self: *InterruptControl) void
```

References: [`InterruptControl`](#type-interruptcontrol)

<a id="fn-interruptcontrol-clear"></a>

### InterruptControl.clear

```zig
pub fn clear(self: *InterruptControl) void
```

References: [`InterruptControl`](#type-interruptcontrol)

<a id="fn-interruptcontrol-isrequested"></a>

### InterruptControl.isRequested

```zig
pub fn isRequested(self: *const InterruptControl) bool
```

References: [`InterruptControl`](#type-interruptcontrol)

<a id="fn-checkexecutionlimits"></a>

## checkExecutionLimits

Per-instruction safepoint for the general dispatch loop. The common case
is one comparison against `instruction_checkpoint`; budgets, interrupt
polls, and recomputation after a budget change share the cold path.

```zig
pub inline fn checkExecutionLimits(comptime State: type, self: *State, thread: *Thread) !void
```

<a id="fn-executioncheckpoint"></a>

## executionCheckpoint

Checkpoint slow path. Interrupts and exhausted budgets leave the
checkpoint in place, so every later safepoint raises again until the host
clears the interrupt or the budget scope ends: Lua code cannot catch them
and keep running.

```zig
pub noinline fn executionCheckpoint(comptime State: type, self: *State, thread: *Thread) !void
```

<a id="fn-checkinterrupt"></a>

## checkInterrupt

Raises `error.Interrupted` when a host thread has requested an interrupt.
Long-running native functions call this periodically.

```zig
pub fn checkInterrupt(comptime State: type, self: *State) !void
```

<a id="fn-instructionbudgetexhausted"></a>

## instructionBudgetExhausted

```zig
pub fn instructionBudgetExhausted(comptime State: type, self: *const State) bool
```

