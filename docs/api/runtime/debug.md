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

- [appendUnhandledErrorDebugDump](#fn-appendunhandlederrordebugdump)
- [appendDebugFrames](#fn-appenddebugframes)
- [appendDebugLocals](#fn-appenddebuglocals)
- [appendDebugVarargs](#fn-appenddebugvarargs)
- [appendDebugUpvalues](#fn-appenddebugupvalues)
- [appendDebugStack](#fn-appenddebugstack)
- [appendDebugValue](#fn-appenddebugvalue)
- [formatTraceback](#fn-formattraceback)
- [formatTracebackWith](#fn-formattracebackwith)
- [indirectFrameCount](#fn-indirectframecount)
- [errorRaisedByLuaCode](#fn-errorraisedbyluacode)
- [messageHandlerCallName](#fn-messagehandlercallname)
- [isCoroutineEntryFrame](#fn-iscoroutineentryframe)
- [chunkId](#fn-chunkid)

## Types

- [TracebackOptions](#type-tracebackoptions)
- [CallName](#type-callname)

## Constants

- [traceback_levels_head](#const-traceback_levels_head)
- [traceback_levels_tail](#const-traceback_levels_tail)
- [coroutine_entry_source](#const-coroutine_entry_source)

<a id="fn-appendunhandlederrordebugdump"></a>

## appendUnhandledErrorDebugDump

```zig
pub fn appendUnhandledErrorDebugDump(comptime State: type, self: *State, thread: *Thread, err: anyerror) !void
```

<a id="fn-appenddebugframes"></a>

## appendDebugFrames

```zig
pub fn appendDebugFrames(comptime State: type, self: *State, out: *std.ArrayList(u8), thread: *Thread) !void
```

<a id="fn-appenddebuglocals"></a>

## appendDebugLocals

```zig
pub fn appendDebugLocals(comptime State: type, self: *State, out: *std.ArrayList(u8), thread: *Thread, frame: CallFrame) !void
```

<a id="fn-appenddebugvarargs"></a>

## appendDebugVarargs

```zig
pub fn appendDebugVarargs(comptime State: type, self: *State, out: *std.ArrayList(u8), frame: CallFrame) !void
```

<a id="fn-appenddebugupvalues"></a>

## appendDebugUpvalues

```zig
pub fn appendDebugUpvalues(comptime State: type, self: *State, out: *std.ArrayList(u8), frame: CallFrame) !void
```

<a id="fn-appenddebugstack"></a>

## appendDebugStack

```zig
pub fn appendDebugStack(comptime State: type, self: *State, out: *std.ArrayList(u8), thread: *Thread) !void
```

<a id="fn-appenddebugvalue"></a>

## appendDebugValue

```zig
pub fn appendDebugValue(comptime State: type, self: *State, out: *std.ArrayList(u8), value: Value) !void
```

<a id="const-traceback_levels_head"></a>

## traceback_levels_head

```zig
pub const traceback_levels_head = 10;
```

<a id="const-traceback_levels_tail"></a>

## traceback_levels_tail

```zig
pub const traceback_levels_tail = 11;
```

<a id="type-tracebackoptions"></a>

## TracebackOptions

```zig
pub const TracebackOptions = struct {
    /// Text placed before `stack traceback:`.
    message: ?[]const u8 = null,
    /// First level shown; level 0 is the function producing the traceback.
    level: usize = 1,
    /// Level 0 is the top frame's native callee; otherwise `level_zero` names it.
    level_zero_is_callee: bool = false,
    level_zero: Value = .nil,
    /// Append the standalone interpreter's `[C]: in ?` entry.
    host_frame: bool = false,
};
```

<a id="fn-formattraceback"></a>

## formatTraceback

Formats a traceback from level 1 without a message, as a message handler sees it.

```zig
pub fn formatTraceback(comptime State: type, self: *State, thread: *Thread, host_frame: bool) ![]u8
```

<a id="fn-formattracebackwith"></a>

## formatTracebackWith

Formats a `luaL_traceback`-style traceback, owned by the caller.

```zig
pub fn formatTracebackWith(comptime State: type, self: *State, thread: *Thread, options: TracebackOptions) ![]u8
```

References: [`TracebackOptions`](#type-tracebackoptions)

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

<a id="fn-chunkid"></a>

## chunkId

Formats a chunk name for messages, as `luaO_chunkid` does.

```zig
pub fn chunkId(buffer: *[chunk_id_size]u8, source: []const u8) []const u8
```

