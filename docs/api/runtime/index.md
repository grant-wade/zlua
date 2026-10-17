# runtime.index

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

- [getTableFromThread](#fn-gettablefromthread)
- [getTableToRegister](#fn-gettabletoregister)
- [rawGet](#fn-rawget)
- [setTable](#fn-settable)
- [setTableValue](#fn-settablevalue)
- [setTableFromThread](#fn-settablefromthread)
- [setTableFromThreadContinuable](#fn-settablefromthreadcontinuable)
- [readableTableKey](#fn-readabletablekey)
- [writableTableKey](#fn-writabletablekey)
- [rawLen](#fn-rawlen)
- [rawSet](#fn-rawset)
- [nextValues](#fn-nextvalues)
- [callPairsMetamethod](#fn-callpairsmetamethod)
- [completeReadyPairsContinuation](#fn-completereadypairscontinuation)
- [ipairsIterValues](#fn-ipairsitervalues)
- [advanceGenericFor](#fn-advancegenericfor)
- [completeReadyGenericForContinuation](#fn-completereadygenericforcontinuation)
- [noIndexMetamethod](#fn-noindexmetamethod)
- [noNewindexMetamethod](#fn-nonewindexmetamethod)

<a id="fn-gettablefromthread"></a>

## getTableFromThread

```zig
pub fn getTableFromThread(self: *State, thread: *Thread, table_value: Value, key_value: Value) !Value
```

<a id="fn-gettabletoregister"></a>

## getTableToRegister

```zig
pub fn getTableToRegister(self: *State, thread: *Thread, dest: bytecode.Register, table_value: Value, key_value: Value) !void
```

<a id="fn-rawget"></a>

## rawGet

```zig
pub fn rawGet(self: *State, table_value: Value, key_value: Value) !Value
```

<a id="fn-settable"></a>

## setTable

```zig
pub fn setTable(self: *State, table_value: Value, key_value: Value, value: Value) !void
```

<a id="fn-settablevalue"></a>

## setTableValue

```zig
pub fn setTableValue(self: *State, table_value: Value, key_value: Value, value: Value) !void
```

<a id="fn-settablefromthread"></a>

## setTableFromThread

```zig
pub fn setTableFromThread(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value) !void
```

<a id="fn-settablefromthreadcontinuable"></a>

## setTableFromThreadContinuable

```zig
pub fn setTableFromThreadContinuable(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value) !void
```

<a id="fn-readabletablekey"></a>

## readableTableKey

```zig
pub fn readableTableKey(self: *State, value: Value) !?Value
```

<a id="fn-writabletablekey"></a>

## writableTableKey

```zig
pub fn writableTableKey(self: *State, value: Value) !Value
```

<a id="fn-rawlen"></a>

## rawLen

```zig
pub fn rawLen(self: *State, value: Value) !Value
```

<a id="fn-rawset"></a>

## rawSet

```zig
pub fn rawSet(self: *State, table_value: Value, key_value: Value, value: Value) !void
```

<a id="fn-nextvalues"></a>

## nextValues

```zig
pub fn nextValues(self: *State, table_value: Value, key_value: Value) ![2]Value
```

<a id="fn-callpairsmetamethod"></a>

## callPairsMetamethod

```zig
pub fn callPairsMetamethod(self: *State, thread: *Thread, op: bytecode.Call, metamethod: Value, value: Value) !void
```

<a id="fn-completereadypairscontinuation"></a>

## completeReadyPairsContinuation

```zig
pub fn completeReadyPairsContinuation(self: *State, thread: *Thread) !bool
```

<a id="fn-ipairsitervalues"></a>

## ipairsIterValues

```zig
pub fn ipairsIterValues(self: *State, thread: *Thread, table_value: Value, key_value: Value) ![2]Value
```

<a id="fn-advancegenericfor"></a>

## advanceGenericFor

```zig
pub fn advanceGenericFor(self: *State, thread: *Thread, op: bytecode.GenericFor, jump_on_nil: bool) !bool
```

<a id="fn-completereadygenericforcontinuation"></a>

## completeReadyGenericForContinuation

```zig
pub fn completeReadyGenericForContinuation(self: *State, thread: *Thread) !bool
```

<a id="fn-noindexmetamethod"></a>

## noIndexMetamethod

```zig
pub inline fn noIndexMetamethod(table: *const Table) bool
```

<a id="fn-nonewindexmetamethod"></a>

## noNewindexMetamethod

```zig
pub inline fn noNewindexMetamethod(table: *const Table) bool
```

