# runtime.debug

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

- [lineForFrame](#fn-lineforframe)
- [appendUnhandledErrorDebugDump](#fn-appendunhandlederrordebugdump)
- [formatTraceback](#fn-formattraceback)
- [indirectFrameCount](#fn-indirectframecount)
- [errorRaisedByLuaCode](#fn-errorraisedbyluacode)
- [messageHandlerCallName](#fn-messagehandlercallname)
- [isCoroutineEntryFrame](#fn-iscoroutineentryframe)
- [currentLine](#fn-currentline)
- [currentExtraArgs](#fn-currentextraargs)
- [currentWhat](#fn-currentwhat)
- [currentFunctionName](#fn-currentfunctionname)
- [currentFunctionNameWhat](#fn-currentfunctionnamewhat)
- [setThreadHook](#fn-setthreadhook)
- [threadHookMask](#fn-threadhookmask)
- [callHook](#fn-callhook)
- [callReturnHook](#fn-callreturnhook)
- [callLineHook](#fn-calllinehook)
- [callCountHook](#fn-callcounthook)
- [tracebackValue](#fn-tracebackvalue)
- [tracebackMessageHandler](#fn-tracebackmessagehandler)
- [snapshotCoroutineErrorTraceback](#fn-snapshotcoroutineerrortraceback)
- [lineForErrorLevel](#fn-lineforerrorlevel)
- [sourceForErrorLevel](#fn-sourceforerrorlevel)

## Types

- [CallName](#type-callname)

## Constants

- [coroutine_entry_source](#const-coroutine_entry_source)

<a id="fn-lineforframe"></a>

## lineForFrame

```zig
pub fn lineForFrame(frame: CallFrame) ?usize
```

<a id="fn-appendunhandlederrordebugdump"></a>

## appendUnhandledErrorDebugDump

```zig
pub fn appendUnhandledErrorDebugDump(self: *State, thread: *Thread, err: anyerror) !void
```

<a id="fn-formattraceback"></a>

## formatTraceback

Formats a traceback from level 1 without a message, as a message handler sees it.

```zig
pub fn formatTraceback(self: *State, thread: *Thread, host_frame: bool) ![]u8
```

<a id="type-callname"></a>

## CallName

```zig
pub const CallName = struct {
    namewhat: []const u8,
    name: []const u8,
};
```

<a id="fn-indirectframecount"></a>

## indirectFrameCount

[Counts](../testing/bench/legacy_process.md#type-counts) frames from `start` that Lua enters through a C call rather than a call instruction.

```zig
pub fn indirectFrameCount(thread: *Thread, start: usize) usize
```

<a id="fn-errorraisedbyluacode"></a>

## errorRaisedByLuaCode

True when Lua code in the top frame, not a native it called, raised the current error.

```zig
pub fn errorRaisedByLuaCode(thread: *Thread) bool
```

<a id="fn-messagehandlercallname"></a>

## messageHandlerCallName

Names a message handler at an error point like `funcnamefromcode`; null inside natives.

```zig
pub fn messageHandlerCallName(thread: *Thread) ?CallName
```

References: [`CallName`](#type-callname)

<a id="const-coroutine_entry_source"></a>

## coroutine_entry_source

```zig
pub const coroutine_entry_source = "=(coroutine entry)";
```

<a id="fn-iscoroutineentryframe"></a>

## isCoroutineEntryFrame

True for the synthetic frame calling a coroutine's non-Lua body, which C Lua lacks.

```zig
pub fn isCoroutineEntryFrame(frame: CallFrame) bool
```

<a id="fn-currentline"></a>

## currentLine

```zig
pub fn currentLine(self: *State, thread: *Thread, level: i64) ?usize
```

<a id="fn-currentextraargs"></a>

## currentExtraArgs

```zig
pub fn currentExtraArgs(self: *State, thread: *Thread, level: i64) ?usize
```

<a id="fn-currentwhat"></a>

## currentWhat

```zig
pub fn currentWhat(self: *State, thread: *Thread, level: i64) []const u8
```

<a id="fn-currentfunctionname"></a>

## currentFunctionName

```zig
pub fn currentFunctionName(self: *State, thread: *Thread, level: i64) ?[]const u8
```

<a id="fn-currentfunctionnamewhat"></a>

## currentFunctionNameWhat

```zig
pub fn currentFunctionNameWhat(self: *State, thread: *Thread, level: i64) ?[]const u8
```

<a id="fn-setthreadhook"></a>

## setThreadHook

```zig
pub fn setThreadHook(self: *State, target: *Thread, hook: Value, mask: []const u8, count: u32) void
```

<a id="fn-threadhookmask"></a>

## threadHookMask

```zig
pub fn threadHookMask(self: *State, thread: *Thread) ![]const u8
```

<a id="fn-callhook"></a>

## callHook

```zig
pub fn callHook(self: *State, thread: *Thread, event: []const u8) !void
```

<a id="fn-callreturnhook"></a>

## callReturnHook

```zig
pub fn callReturnHook(self: *State, thread: *Thread, name: ?[]const u8) !void
```

<a id="fn-calllinehook"></a>

## callLineHook

```zig
pub fn callLineHook(self: *State, thread: *Thread) !void
```

<a id="fn-callcounthook"></a>

## callCountHook

```zig
pub fn callCountHook(self: *State, thread: *Thread) !void
```

<a id="fn-tracebackvalue"></a>

## tracebackValue

```zig
pub fn tracebackValue(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-tracebackmessagehandler"></a>

## tracebackMessageHandler

The standalone interpreter's `msghandler` from `lua.c`.

```zig
pub fn tracebackMessageHandler(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-snapshotcoroutineerrortraceback"></a>

## snapshotCoroutineErrorTraceback

```zig
pub fn snapshotCoroutineErrorTraceback(self: *State, target: *Thread) ![]const u8
```

<a id="fn-lineforerrorlevel"></a>

## lineForErrorLevel

```zig
pub fn lineForErrorLevel(self: *State, thread: *Thread, level: usize) ?usize
```

<a id="fn-sourceforerrorlevel"></a>

## sourceForErrorLevel

```zig
pub fn sourceForErrorLevel(self: *State, thread: *Thread, level: usize) ?[]const u8
```

