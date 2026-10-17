# runtime.coroutine

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
- [stdlib.string.format](../stdlib/string/format.md)
- [stdlib.string.pack](../stdlib/string/pack.md)
- [stdlib.string.pattern](../stdlib/string/pattern.md)
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
- [runtime.budget](../runtime/budget.md)
- [runtime.strings](../runtime/strings.md)
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
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Functions

- [coroutineCreate](#fn-coroutinecreate)
- [coroutineResume](#fn-coroutineresume)
- [isYieldable](#fn-isyieldable)
- [yieldRejection](#fn-yieldrejection)
- [exposeThread](#fn-exposethread)
- [suspendCoroutine](#fn-suspendcoroutine)
- [coroutineYield](#fn-coroutineyield)
- [coroutineStatus](#fn-coroutinestatus)
- [coroutineRunning](#fn-coroutinerunning)
- [coroutineIsYieldable](#fn-coroutineisyieldable)
- [coroutineClose](#fn-coroutineclose)
- [coroutineWrap](#fn-coroutinewrap)
- [callCoroutineWrapper](#fn-callcoroutinewrapper)
- [newCoroutineThread](#fn-newcoroutinethread)
- [resumeCoroutine](#fn-resumecoroutine)
- [copyStackSlice](#fn-copystackslice)
- [closeCoroutineFromHost](#fn-closecoroutinefromhost)

<a id="fn-coroutinecreate"></a>

## coroutineCreate

```zig
pub fn coroutineCreate(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-coroutineresume"></a>

## coroutineResume

```zig
pub fn coroutineResume(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-isyieldable"></a>

## isYieldable

```zig
pub fn isYieldable(thread: *const Thread) bool
```

<a id="fn-yieldrejection"></a>

## yieldRejection

Returns the Lua error message for a yield from `thread`, or null when it can yield.

```zig
pub fn yieldRejection(thread: *const Thread) ?[]const u8
```

<a id="fn-exposethread"></a>

## exposeThread

Marks `thread` as reachable from a Lua value so it outlives its host call.

```zig
pub fn exposeThread(thread: *Thread) !void
```

<a id="fn-suspendcoroutine"></a>

## suspendCoroutine

```zig
pub fn suspendCoroutine(self: *State, thread: *Thread, op: bytecode.Call, values: []const Value) !void
```

<a id="fn-coroutineyield"></a>

## coroutineYield

```zig
pub fn coroutineYield(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-coroutinestatus"></a>

## coroutineStatus

```zig
pub fn coroutineStatus(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-coroutinerunning"></a>

## coroutineRunning

```zig
pub fn coroutineRunning(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-coroutineisyieldable"></a>

## coroutineIsYieldable

```zig
pub fn coroutineIsYieldable(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-coroutineclose"></a>

## coroutineClose

```zig
pub fn coroutineClose(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-coroutinewrap"></a>

## coroutineWrap

```zig
pub fn coroutineWrap(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-callcoroutinewrapper"></a>

## callCoroutineWrapper

```zig
pub fn callCoroutineWrapper(self: *State, thread: *Thread, op: bytecode.Call, target: *Thread) !void
```

<a id="fn-newcoroutinethread"></a>

## newCoroutineThread

```zig
pub fn newCoroutineThread(self: *State, entry: Value) !*Thread
```

<a id="fn-resumecoroutine"></a>

## resumeCoroutine

```zig
pub fn resumeCoroutine(self: *State, target: *Thread, args: []const Value) !CoroutineResumeResult
```

<a id="fn-copystackslice"></a>

## copyStackSlice

```zig
pub fn copyStackSlice(self: *State, thread: *Thread, base: usize, count: usize) ![]Value
```

<a id="fn-closecoroutinefromhost"></a>

## closeCoroutineFromHost

```zig
pub fn closeCoroutineFromHost(self: *State, target: *Thread, error_value: ?Value) !?Value
```

