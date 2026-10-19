# api.userdata

## Navigation

- [API Index](../README.md)
- Parent: [api](../api.md)

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

## Functions

- [UserdataOptions](#fn-userdataoptions)
- [UserdataPtrOptions](#fn-userdataptroptions)
- [UserdataSnapshotHooks](#fn-userdatasnapshothooks)
- [Userdata](#fn-userdata)
- [create](#fn-create)
- [wrapPtr](#fn-wrapptr)
- [isReceiver](#fn-isreceiver)
- [beginScope](#fn-beginscope)
- [endScope](#fn-endscope)
- [typeId](#fn-typeid)
- [payloadPtr](#fn-payloadptr)
- [isHandle](#fn-ishandle)

## Types

- [AnyUserdata](#type-anyuserdata)

<a id="fn-userdataoptions"></a>

## UserdataOptions

```zig
pub fn UserdataOptions(comptime T: type) type
```

<a id="fn-userdataptroptions"></a>

## UserdataPtrOptions

```zig
pub fn UserdataPtrOptions(comptime T: type) type
```

<a id="fn-userdatasnapshothooks"></a>

## UserdataSnapshotHooks

Snapshot copy/dispose hooks for userdata payloads. Copies must own all nested storage and
must not retain VM pointers or reenter snapshot operations. Hooks must be thread-safe:
concurrent `Snapshot.newState` calls may copy one payload, and disposal runs on any thread.

```zig
pub fn UserdataSnapshotHooks(comptime T: type) type
```

<a id="fn-userdata"></a>

## Userdata

Typed userdata handle for payload type `T`.

```zig
pub fn Userdata(comptime T: type) type
```

<a id="type-anyuserdata"></a>

## AnyUserdata

Rooted userdata handle with an unknown payload type.

```zig
pub const AnyUserdata = struct {
    ref: Ref,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-anyuserdata-deinit) | `self: *AnyUserdata` | `void` |  |
| [as](#fn-anyuserdata-as) | `self: AnyUserdata, comptime T: type` | `!Userdata(T)` | Returns a new typed handle after checking the payload type. |

<a id="fn-anyuserdata-deinit"></a>

### AnyUserdata.deinit

```zig
pub fn deinit(self: *AnyUserdata) void
```

References: [`AnyUserdata`](#type-anyuserdata)

<a id="fn-anyuserdata-as"></a>

### AnyUserdata.as

Returns a new typed handle after checking the payload type.

```zig
pub fn as(self: AnyUserdata, comptime T: type) !Userdata(T)
```

References: [`AnyUserdata`](#type-anyuserdata)

<a id="fn-create"></a>

## create

```zig
pub fn create(state: *State, comptime T: type, value: T, options: UserdataOptions(T)) !Userdata(T)
```

<a id="fn-wrapptr"></a>

## wrapPtr

```zig
pub fn wrapPtr(state: *State, comptime T: type, ptr: *T, options: UserdataPtrOptions(T)) !Userdata(T)
```

<a id="fn-isreceiver"></a>

## isReceiver

```zig
pub fn isReceiver(comptime T: type, comptime Receiver: type) bool
```

<a id="fn-beginscope"></a>

## beginScope

```zig
pub fn beginScope(state: *runtime.State, scope: *runtime_types.UserdataScope, userdata: *runtime.Userdata, readonly: bool) !void
```

References: [`runtime.State`](../runtime.md#alias-state), [`runtime.Userdata`](../runtime.md#alias-userdata)

<a id="fn-endscope"></a>

## endScope

```zig
pub fn endScope(state: *runtime.State, scope: *runtime_types.UserdataScope) void
```

References: [`runtime.State`](../runtime.md#alias-state)

<a id="fn-typeid"></a>

## typeId

```zig
pub fn typeId(comptime T: type) usize
```

<a id="fn-payloadptr"></a>

## payloadPtr

```zig
pub fn payloadPtr(comptime T: type, raw: *runtime.Userdata) !*T
```

References: [`runtime.Userdata`](../runtime.md#alias-userdata)

<a id="fn-ishandle"></a>

## isHandle

```zig
pub fn isHandle(comptime T: type) bool
```

