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
- [runtime.state](../runtime/state.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.host](../runtime/host.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.io](../runtime/io.md)
- [runtime.load](../runtime/load.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.index](../runtime/index.md)
- [runtime.operators](../runtime/operators.md)
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
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
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
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Functions

- [executionCheckpoint](#fn-executioncheckpoint)
- [checkInterrupt](#fn-checkinterrupt)
- [runThreadUntil](#fn-runthreaduntil)
- [interruptControl](#fn-interruptcontrol)
- [interruptRequested](#fn-interruptrequested)
- [clearInterrupt](#fn-clearinterrupt)
- [instructionBudgetUsed](#fn-instructionbudgetused)
- [resetInstructionBudget](#fn-resetinstructionbudget)
- [beginCallInstructionBudget](#fn-begincallinstructionbudget)
- [endCallInstructionBudget](#fn-endcallinstructionbudget)
- [consumeInterrupt](#fn-consumeinterrupt)
- [get](#fn-get)
- [set](#fn-set)
- [absoluteRegister](#fn-absoluteregister)
- [jumpThread](#fn-jumpthread)
- [jumpThreadMaybeFast](#fn-jumpthreadmaybefast)
- [forValueName](#fn-forvaluename)
- [assertProtoPrepared](#fn-assertprotoprepared)

## Types

- [InterruptControl](#type-interruptcontrol)
- [ForValueKind](#type-forvaluekind)

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

<a id="fn-executioncheckpoint"></a>

## executionCheckpoint

Interrupts and exhausted budgets leave the checkpoint in place so every later
safepoint raises again; Lua code cannot catch them and keep running.

```zig
pub noinline fn executionCheckpoint(self: *State, thread: *Thread) !void
```

<a id="fn-checkinterrupt"></a>

## checkInterrupt

Polled periodically by long-running native functions.

```zig
pub fn checkInterrupt(self: *State) !void
```

<a id="fn-runthreaduntil"></a>

## runThreadUntil

```zig
pub fn runThreadUntil(self: *State, thread: *Thread, target_frame_count: usize) anyerror!void
```

<a id="fn-interruptcontrol"></a>

## interruptControl

Allocates the shared interrupt control on first use; polling starts at the next safepoint.

```zig
pub fn interruptControl(self: *State) !*InterruptControl
```

References: [`InterruptControl`](#type-interruptcontrol)

<a id="fn-interruptrequested"></a>

## interruptRequested

```zig
pub inline fn interruptRequested(self: *const State) bool
```

<a id="fn-clearinterrupt"></a>

## clearInterrupt

```zig
pub fn clearInterrupt(self: *State) void
```

<a id="fn-instructionbudgetused"></a>

## instructionBudgetUsed

```zig
pub fn instructionBudgetUsed(self: *const State) u64
```

<a id="fn-resetinstructionbudget"></a>

## resetInstructionBudget

Restarts the cumulative `max_instructions` budget.

```zig
pub fn resetInstructionBudget(self: *State) void
```

<a id="fn-begincallinstructionbudget"></a>

## beginCallInstructionBudget

Limits a host call, including nested calls and coroutines, to `max` further
instructions. Returns the enclosing deadline for `endCallInstructionBudget`.

```zig
pub fn beginCallInstructionBudget(self: *State, max: u64) ?u64
```

<a id="fn-endcallinstructionbudget"></a>

## endCallInstructionBudget

Restores the deadline returned by `beginCallInstructionBudget`.

```zig
pub fn endCallInstructionBudget(self: *State, previous: ?u64) void
```

<a id="fn-consumeinterrupt"></a>

## consumeInterrupt

```zig
pub fn consumeInterrupt(self: *State) void
```

<a id="fn-get"></a>

## get

```zig
pub fn get(_: *State, thread: *Thread, register: usize) Value
```

<a id="fn-set"></a>

## set

```zig
pub fn set(_: *State, thread: *Thread, register: usize, value: Value) void
```

<a id="fn-absoluteregister"></a>

## absoluteRegister

```zig
pub fn absoluteRegister(_: *State, thread: *Thread, register: usize) usize
```

<a id="fn-jumpthread"></a>

## jumpThread

```zig
pub fn jumpThread(self: *State, thread: *Thread, offset: bytecode.JumpOffset, auto_gc: bool) !void
```

<a id="fn-jumpthreadmaybefast"></a>

## jumpThreadMaybeFast

```zig
pub fn jumpThreadMaybeFast(self: *State, thread: *Thread, offset: bytecode.JumpOffset, auto_gc: bool) !void
```

<a id="type-forvaluekind"></a>

## ForValueKind

```zig
pub const ForValueKind = enum {
    initial,
    limit,
    step,
};
```

<a id="fn-forvaluename"></a>

## forValueName

```zig
pub fn forValueName(kind: ForValueKind) []const u8
```

References: [`ForValueKind`](#type-forvaluekind)

<a id="fn-assertprotoprepared"></a>

## assertProtoPrepared

```zig
pub fn assertProtoPrepared(proto: *const proto_mod.Proto) void
```

