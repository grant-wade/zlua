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
- [chunkId](#fn-chunkid)

## Types

- [TracebackOptions](#type-tracebackoptions)
- [CallName](#type-callname)

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

<a id="type-tracebackoptions"></a>

## TracebackOptions

```zig
pub const TracebackOptions = struct {
    /// Text placed before `stack traceback:`.
    message: ?[]const u8 = null,
    /// First level shown. Level 0 is the function producing the traceback.
    level: usize = 1,
    /// Level 0 is the native function called by the top frame's current
    /// instruction. Otherwise it is not on the thread, as for a message
    /// handler, and `level_zero` names it.
    level_zero_is_callee: bool = false,
    level_zero: Value = .nil,
    /// End with the `[C]: in ?` entry that the standalone interpreter
    /// reports for its own call.
    host_frame: bool = false,
};
```

<a id="fn-formattraceback"></a>

## formatTraceback

Formats a `luaL_traceback`-style traceback of `thread` without a message,
starting at level 1 as a message handler sees it. See `formatTracebackWith`.

```zig
pub fn formatTraceback(comptime State: type, self: *State, thread: *Thread, host_frame: bool) ![]u8
```

<a id="fn-formattracebackwith"></a>

## formatTracebackWith

Formats a `luaL_traceback`-style traceback: `stack traceback:` followed
by one line per level, innermost first. Called at an error point it shows
the native function that raised the error and the Lua frames that were
active. Names come from the calling instruction, as in Lua 5.5, or else
from the global and loaded-module tables. The caller owns the returned
slice, allocated with `self.allocator`.

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

Frames from `start` up that Lua would have entered through a C call,
such as a metamethod or a message handler, rather than a call instruction.

```zig
pub fn indirectFrameCount(thread: *Thread, start: usize) usize
```

<a id="fn-errorraisedbyluacode"></a>

## errorRaisedByLuaCode

True when Lua code in the top frame raised the current error, rather
than a native function it called.

```zig
pub fn errorRaisedByLuaCode(thread: *Thread) bool
```

<a id="fn-messagehandlercallname"></a>

## messageHandlerCallName

Names a message handler called at an error point the way Lua names a
function from its caller's current instruction (`funcnamefromcode`).
An error raised inside a native function leaves the handler unnamed.

```zig
pub fn messageHandlerCallName(thread: *Thread) ?CallName
```

References: [`CallName`](#type-callname)

<a id="fn-chunkid"></a>

## chunkId

Formats a chunk name for messages, as `luaO_chunkid` does.

```zig
pub fn chunkId(buffer: *[chunk_id_size]u8, source: []const u8) []const u8
```

