# runtime.call

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

- [callOneResult](#fn-calloneresult)
- [callOneMetamethodWithContinuation](#fn-callonemetamethodwithcontinuation)
- [callOneMetamethod](#fn-callonemetamethod)
- [callOneNamed](#fn-callonenamed)
- [completeReadyCallOneContinuation](#fn-completereadycallonecontinuation)
- [protectedCall](#fn-protectedcall)
- [protectedCallContextWithErrors](#fn-protectedcallcontextwitherrors)
- [runProtectedCall](#fn-runprotectedcall)
- [readyProtectedContinuationIndex](#fn-readyprotectedcontinuationindex)
- [completeReadyProtectedContinuation](#fn-completereadyprotectedcontinuation)
- [completeProtectedContinuationError](#fn-completeprotectedcontinuationerror)
- [collectArgs](#fn-collectargs)
- [resolveReturnCount](#fn-resolvereturncount)
- [prepareClosureFrame](#fn-prepareclosureframe)
- [noteCaughtError](#fn-notecaughterror)
- [applyMessageHandler](#fn-applymessagehandler)
- [checkCStack](#fn-checkcstack)
- [callCollect](#fn-callcollect)
- [callValue](#fn-callvalue)
- [runtimeNativeCall](#fn-runtimenativecall)
- [nativeCallInfo](#fn-nativecallinfo)
- [invokeValue](#fn-invokevalue)
- [nativeStackFits](#fn-nativestackfits)
- [callStackValueLimit](#fn-callstackvaluelimit)
- [tailCallValue](#fn-tailcallvalue)
- [returnFromFrame](#fn-returnfromframe)
- [namedVarargRead](#fn-namedvarargread)
- [resolveResultCount](#fn-resolveresultcount)
- [loadVarargs](#fn-loadvarargs)
- [caughtErrorValue](#fn-caughterrorvalue)
- [completeReadyTailCallContinuation](#fn-completereadytailcallcontinuation)
- [callNative](#fn-callnative)
- [isRuntimeError](#fn-isruntimeerror)
- [hasPendingContinuations](#fn-haspendingcontinuations)

<a id="fn-calloneresult"></a>

## callOneResult

```zig
pub fn callOneResult(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!Value
```

<a id="fn-callonemetamethodwithcontinuation"></a>

## callOneMetamethodWithContinuation

```zig
pub fn callOneMetamethodWithContinuation(self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value
```

<a id="fn-callonemetamethod"></a>

## callOneMetamethod

```zig
pub fn callOneMetamethod(self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value) anyerror!Value
```

<a id="fn-callonenamed"></a>

## callOneNamed

Calls `callable` for one result; a Lua callee reports `namewhat 'name'`.

```zig
pub fn callOneNamed(self: *State, thread: *Thread, name: []const u8, namewhat: []const u8, callable: Value, args: []const Value) anyerror!Value
```

<a id="fn-completereadycallonecontinuation"></a>

## completeReadyCallOneContinuation

```zig
pub fn completeReadyCallOneContinuation(self: *State, thread: *Thread) !bool
```

<a id="fn-protectedcall"></a>

## protectedCall

```zig
pub fn protectedCall(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!ProtectedCallResult
```

<a id="fn-protectedcallcontextwitherrors"></a>

## protectedCallContextWithErrors

```zig
pub fn protectedCallContextWithErrors(self: *State, thread: *Thread) ProtectedCallContext
```

<a id="fn-runprotectedcall"></a>

## runProtectedCall

```zig
pub fn runProtectedCall(self: *State, thread: *Thread, context: ProtectedCallContext, callable: Value, args: []const Value) anyerror!ProtectedCallResult
```

<a id="fn-readyprotectedcontinuationindex"></a>

## readyProtectedContinuationIndex

```zig
pub fn readyProtectedContinuationIndex(thread: *Thread) ?usize
```

<a id="fn-completereadyprotectedcontinuation"></a>

## completeReadyProtectedContinuation

```zig
pub fn completeReadyProtectedContinuation(self: *State, thread: *Thread) !bool
```

<a id="fn-completeprotectedcontinuationerror"></a>

## completeProtectedContinuationError

```zig
pub fn completeProtectedContinuationError(self: *State, thread: *Thread) !bool
```

<a id="fn-collectargs"></a>

## collectArgs

```zig
pub fn collectArgs(self: *State, thread: *Thread, op: bytecode.Call, first: u32) ![]Value
```

<a id="fn-resolvereturncount"></a>

## resolveReturnCount

```zig
pub fn resolveReturnCount(self: *State, count: u16, available: usize) !usize
```

<a id="fn-prepareclosureframe"></a>

## prepareClosureFrame

```zig
pub fn prepareClosureFrame(self: *State, thread: *Thread, closure: *Closure, source_base: usize, frame_base: usize, arg_count: usize, return_start: usize, return_count: u16) !CallFrame
```

<a id="fn-notecaughterror"></a>

## noteCaughtError

Records stack overflow and memory errors caught from Lua execution; memory
errors skip message handlers as in Lua.

```zig
pub fn noteCaughtError(self: *State, err: anyerror) void
```

<a id="fn-applymessagehandler"></a>

## applyMessageHandler

Runs the message handler on top of the failing frames, like `luaG_errormsg`.
Handler errors retry until Lua's C-call limit yields "error in error handling".

```zig
pub fn applyMessageHandler(self: *State, thread: *Thread) !void
```

<a id="fn-checkcstack"></a>

## checkCStack

```zig
pub fn checkCStack(self: *State, thread: *Thread) !void
```

<a id="fn-callcollect"></a>

## callCollect

```zig
pub fn callCollect(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror![]Value
```

<a id="fn-callvalue"></a>

## callValue

```zig
pub fn callValue(self: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-runtimenativecall"></a>

## runtimeNativeCall

Native code the runtime runs on top of the current frame, such as error handling.

```zig
pub fn runtimeNativeCall(thread: *Thread) types.NativeCall
```

<a id="fn-nativecallinfo"></a>

## nativeCallInfo

```zig
pub fn nativeCallInfo(thread: *Thread, resolved: bytecode.Call, outer: ?types.NativeCall, name: ?[]const u8, namewhat: ?[]const u8, extra_args: usize) types.NativeCall
```

<a id="fn-invokevalue"></a>

## invokeValue

```zig
pub fn invokeValue(self: *State, thread: *Thread, resolved: bytecode.Call, depth: usize) anyerror!void
```

<a id="fn-nativestackfits"></a>

## nativeStackFits

Like `lua_checkstack`, above the arguments of native call `op`.

```zig
pub fn nativeStackFits(self: *const State, thread: *const Thread, op: bytecode.Call, count: usize) bool
```

<a id="fn-callstackvaluelimit"></a>

## callStackValueLimit

```zig
pub fn callStackValueLimit(self: *const State, thread: *const Thread) usize
```

<a id="fn-tailcallvalue"></a>

## tailCallValue

```zig
pub fn tailCallValue(self: *State, thread: *Thread, op: bytecode.Call) anyerror!void
```

<a id="fn-returnfromframe"></a>

## returnFromFrame

```zig
pub fn returnFromFrame(self: *State, thread: *Thread, first: u32, count: u16) !void
```

<a id="fn-namedvarargread"></a>

## namedVarargRead

```zig
pub fn namedVarargRead(varargs: []const Value, key: Value) Value
```

<a id="fn-resolveresultcount"></a>

## resolveResultCount

```zig
pub fn resolveResultCount(self: *State, thread: *Thread, source_start: usize, count: u16) !usize
```

<a id="fn-loadvarargs"></a>

## loadVarargs

```zig
pub fn loadVarargs(self: *State, thread: *Thread, op: bytecode.Vararg) !void
```

<a id="fn-caughterrorvalue"></a>

## caughtErrorValue

Like `luaG_errormsg` without a handler: nil becomes `<no error object>`.

```zig
pub fn caughtErrorValue(self: *State, value: Value) !Value
```

<a id="fn-completereadytailcallcontinuation"></a>

## completeReadyTailCallContinuation

```zig
pub fn completeReadyTailCallContinuation(self: *State, thread: *Thread) !bool
```

<a id="fn-callnative"></a>

## callNative

```zig
pub fn callNative(self: *State, native: NativeFn, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-isruntimeerror"></a>

## isRuntimeError

```zig
pub fn isRuntimeError(err: anyerror) bool
```

<a id="fn-haspendingcontinuations"></a>

## hasPendingContinuations

```zig
pub inline fn hasPendingContinuations(thread: *const Thread) bool
```

