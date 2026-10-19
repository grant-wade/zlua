# runtime.budget

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

## Types

- [InterruptControl](#type-interruptcontrol)
- [Budget](#type-budget)

<a id="type-interruptcontrol"></a>

## InterruptControl

Interrupt request shared with host threads. Heap-allocated so its address
survives moves of the owning state.

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

<a id="type-budget"></a>

## Budget

[Instruction](../compile/bytecode.md#type-instruction) counting, `max_instructions` and per-call budgets, and host interrupts.

```zig
pub const Budget = struct {
    instructions: u64 = 0,
    /// `instructions` at the last budget reset.
    base: u64 = 0,
    /// Deadline of the innermost budgeted host call, narrowed by enclosing ones.
    call_deadline: ?u64 = null,
    /// `instructions` at which `checkpointReached` runs; zero forces a recompute.
    checkpoint: u64 = 0,
    /// Allocated on first use.
    interrupt: ?*InterruptControl = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [checkLimits](#fn-budget-checklimits) | `budget: *Budget, thread: *Thread` | `!void` | Per-instruction safepoint; the hot path is one comparison against &#96;checkpoint&#96;. |
| [checkInterrupt](#fn-budget-checkinterrupt) | `budget: *Budget` | `!void` | Polled periodically by long-running native functions. |
| [interruptControl](#fn-budget-interruptcontrol) | `budget: *Budget` | `!*InterruptControl` |  |
| [interruptRequested](#fn-budget-interruptrequested) | `budget: *const Budget` | `bool` |  |
| [clearInterrupt](#fn-budget-clearinterrupt) | `budget: *Budget` | `void` |  |
| [fastLoopInterrupted](#fn-budget-fastloopinterrupted) | `budget: *Budget` | `bool` |  |
| [active](#fn-budget-active) | `budget: *const Budget` | `bool` | The uncounted fast loop is disabled while any instruction budget applies. |
| [used](#fn-budget-used) | `budget: *const Budget` | `u64` |  |
| [reset](#fn-budget-reset) | `budget: *Budget` | `void` | Restarts the cumulative &#96;max_instructions&#96; budget. |
| [beginCall](#fn-budget-begincall) | `budget: *Budget, max: u64` | `?u64` | Limits a host call, including nested calls and coroutines, to &#96;max&#96; further instructions. Returns the enclosing deadline for &#96;endCall&#96;. |
| [endCall](#fn-budget-endcall) | `budget: *Budget, previous: ?u64` | `void` | Restores the deadline returned by &#96;beginCall&#96;. |
| [consumeInterrupt](#fn-budget-consumeinterrupt) | `budget: *Budget` | `void` |  |

<a id="fn-budget-checklimits"></a>

### Budget.checkLimits

Per-instruction safepoint; the hot path is one comparison against `checkpoint`.

```zig
pub inline fn checkLimits(budget: *Budget, thread: *Thread) !void
```

References: [`Budget`](#type-budget)

<a id="fn-budget-checkinterrupt"></a>

### Budget.checkInterrupt

Polled periodically by long-running native functions.

```zig
pub fn checkInterrupt(budget: *Budget) !void
```

References: [`Budget`](#type-budget)

<a id="fn-budget-interruptcontrol"></a>

### Budget.interruptControl

```zig
pub fn interruptControl(budget: *Budget) !*InterruptControl
```

References: [`Budget`](#type-budget), [`InterruptControl`](#type-interruptcontrol)

<a id="fn-budget-interruptrequested"></a>

### Budget.interruptRequested

```zig
pub inline fn interruptRequested(budget: *const Budget) bool
```

References: [`Budget`](#type-budget)

<a id="fn-budget-clearinterrupt"></a>

### Budget.clearInterrupt

```zig
pub fn clearInterrupt(budget: *Budget) void
```

References: [`Budget`](#type-budget)

<a id="fn-budget-fastloopinterrupted"></a>

### Budget.fastLoopInterrupted

```zig
pub inline fn fastLoopInterrupted(budget: *Budget) bool
```

References: [`Budget`](#type-budget)

<a id="fn-budget-active"></a>

### Budget.active

The uncounted fast loop is disabled while any instruction budget applies.

```zig
pub inline fn active(budget: *const Budget) bool
```

References: [`Budget`](#type-budget)

<a id="fn-budget-used"></a>

### Budget.used

```zig
pub fn used(budget: *const Budget) u64
```

References: [`Budget`](#type-budget)

<a id="fn-budget-reset"></a>

### Budget.reset

Restarts the cumulative `max_instructions` budget.

```zig
pub fn reset(budget: *Budget) void
```

References: [`Budget`](#type-budget)

<a id="fn-budget-begincall"></a>

### Budget.beginCall

Limits a host call, including nested calls and coroutines, to `max` further
instructions. Returns the enclosing deadline for `endCall`.

```zig
pub fn beginCall(budget: *Budget, max: u64) ?u64
```

References: [`Budget`](#type-budget)

<a id="fn-budget-endcall"></a>

### Budget.endCall

Restores the deadline returned by `beginCall`.

```zig
pub fn endCall(budget: *Budget, previous: ?u64) void
```

References: [`Budget`](#type-budget)

<a id="fn-budget-consumeinterrupt"></a>

### Budget.consumeInterrupt

```zig
pub fn consumeInterrupt(budget: *Budget) void
```

References: [`Budget`](#type-budget)

