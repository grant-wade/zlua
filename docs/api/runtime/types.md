# runtime.types

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

- [RuntimeError](#type-runtimeerror)
- [Value](#type-value)
- [String](#type-string)
- [AllocatorLifetime](#type-allocatorlifetime)
- [UserdataPayload](#type-userdatapayload)
- [ProtectedCallResult](#type-protectedcallresult)
- [CallbackReturns](#type-callbackreturns)
- [ApiCallbackContext](#type-apicallbackcontext)
- [RuntimeErrorPayload](#type-runtimeerrorpayload)
- [ProtectedCallContext](#type-protectedcallcontext)
- [NativeMark](#type-nativemark)
- [ProtectedContinuation](#type-protectedcontinuation)
- [GenericForContinuation](#type-genericforcontinuation)
- [PairsContinuation](#type-pairscontinuation)
- [BranchContinuation](#type-branchcontinuation)
- [TailCallContinuation](#type-tailcallcontinuation)
- [CallOneContinuationResult](#type-callonecontinuationresult)
- [ConcatContinuation](#type-concatcontinuation)
- [CallOneContinuation](#type-callonecontinuation)
- [CoroutineResumeResult](#type-coroutineresumeresult)
- [Chunk](#type-chunk)
- [Closure](#type-closure)
- [Upvalue](#type-upvalue)
- [TableEntry](#type-tableentry)
- [MetaEvent](#type-metaevent)
- [TableArray](#type-tablearray)
- [Table](#type-table)
- [UserdataScope](#type-userdatascope)
- [ValueRoots](#type-valueroots)
- [Userdata](#type-userdata)
- [TableFinalizer](#type-tablefinalizer)
- [FinalizerObject](#type-finalizerobject)
- [Thread](#type-thread)
- [ThreadStatus](#type-threadstatus)
- [NativeCall](#type-nativecall)
- [CallFrame](#type-callframe)
- [FrameExtra](#type-frameextra)
- [AddressContext](#type-addresscontext)
- [GcColor](#type-gccolor)
- [GcAge](#type-gcage)
- [GcHeader](#type-gcheader)
- [GcObject](#type-gcobject)
- [GcPhase](#type-gcphase)
- [GcCycle](#type-gccycle)
- [GcGenerations](#type-gcgenerations)
- [GcMode](#type-gcmode)
- [GcParam](#type-gcparam)
- [GcParams](#type-gcparams)
- [WeakMode](#type-weakmode)
- [RuntimeAllocationStats](#type-runtimeallocationstats)

## Constants

- [UserdataFinalizer](#const-userdatafinalizer)
- [UserdataDeinit](#const-userdatadeinit)
- [UserdataSnapshotCopy](#const-userdatasnapshotcopy)
- [ApiCallbackDispatchFn](#const-apicallbackdispatchfn)

## Aliases

- [TableHashPart](#alias-tablehashpart)

## Imports

- [NativeFn](#import-nativefn) `@import("native_fn.zig")`

<a id="type-runtimeerror"></a>

## RuntimeError

```zig
pub const RuntimeError = error{
    RuntimeError,
    StackOverflow,
    UnsupportedOpcode,
    OutOfMemory,
};
```

<a id="type-value"></a>

## Value

```zig
pub const Value = union(enum(u8)) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    string: *const String,
    table: *Table,
    userdata: *Userdata,
    closure: *Closure,
    thread: *Thread,
    coroutine_wrapper: *Thread,
    gmatch_iterator: *Table,
    native_print,
    native_tostring,
    native_getmetatable,
    native_setmetatable,
    native_rawequal,
    native_rawget,
    native_rawset,
    native_rawlen,
    native_next,
    native_pairs,
    native_ipairs,
    native_ipairs_iter,
    native_table_create,
    native_select,
    native_assert,
    native_error,
    native_pcall,
    native_xpcall,
    native_collectgarbage,
    native_debug_traceback,
    native_coroutine_create,
    native_coroutine_resume,
    native_coroutine_yield,
    native_coroutine_status,
    native_coroutine_running,
    native_coroutine_isyieldable,
    native_coroutine_close,
    native_coroutine_wrap,
    native: NativeFn,
    api_callback: usize,
};
```

<a id="import-nativefn"></a>

## NativeFn

```zig
pub const NativeFn = @import("native_fn.zig").NativeFn;
```

<a id="type-string"></a>

## String

A Lua string, followed by its bytes in the same allocation. [Strings](../runtime/strings.md#type-strings) of at most
`short_limit` bytes are always interned.

```zig
pub const String = extern struct {
    gc: GcHeader = .{},
    len: usize,
    /// `table_index.hashStringKey` of the bytes, valid once `hashed` is set.
    hash: u32 = 0,
    hashed: bool = false,
    /// In the state's intern set.
    interned: bool = false,
    /// From the static catalog; never collected or written.
    static: bool = false,
    /// Hash-part entry index where this key was last found by a field access, or `no_field_hint`.
    field_hint: u8 = no_field_hint,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [short_limit](#const-string-short_limit) |  |  |  |
| [no_field_hint](#const-string-no_field_hint) |  |  |  |
| [bytes](#fn-string-bytes) | `self: *const String` | `[]const u8` |  |
| [bytesMut](#fn-string-bytesmut) | `self: *String` | `[]u8` |  |
| [isShort](#fn-string-isshort) | `self: *const String` | `bool` |  |
| [eql](#fn-string-eql) | `self: *const String, other: *const String` | `bool` |  |
| [eqlBytes](#fn-string-eqlbytes) | `self: *const String, other: []const u8` | `bool` |  |
| [tableHash](#fn-string-tablehash) | `self: *const String` | `u32` |  |
| [gcBytes](#fn-string-gcbytes) | `self: *const String` | `usize` |  |

<a id="const-string-short_limit"></a>

### String.short_limit

```zig
pub const short_limit = 40;
```

<a id="const-string-no_field_hint"></a>

### String.no_field_hint

```zig
pub const no_field_hint = std.math.maxInt(u8);
```

<a id="fn-string-bytes"></a>

### String.bytes

```zig
pub inline fn bytes(self: *const String) []const u8
```

References: [`String`](#type-string)

<a id="fn-string-bytesmut"></a>

### String.bytesMut

```zig
pub inline fn bytesMut(self: *String) []u8
```

References: [`String`](#type-string)

<a id="fn-string-isshort"></a>

### String.isShort

```zig
pub inline fn isShort(self: *const String) bool
```

References: [`String`](#type-string)

<a id="fn-string-eql"></a>

### String.eql

```zig
pub inline fn eql(self: *const String, other: *const String) bool
```

References: [`String`](#type-string)

<a id="fn-string-eqlbytes"></a>

### String.eqlBytes

```zig
pub inline fn eqlBytes(self: *const String, other: []const u8) bool
```

References: [`String`](#type-string)

<a id="fn-string-tablehash"></a>

### String.tableHash

```zig
pub inline fn tableHash(self: *const String) u32
```

References: [`String`](#type-string)

<a id="fn-string-gcbytes"></a>

### String.gcBytes

```zig
pub inline fn gcBytes(self: *const String) usize
```

References: [`String`](#type-string)

<a id="const-userdatafinalizer"></a>

## UserdataFinalizer

```zig
pub const UserdataFinalizer = *const fn (*anyopaque, ?*const anyopaque) void;
```

<a id="const-userdatadeinit"></a>

## UserdataDeinit

```zig
pub const UserdataDeinit = *const fn (std.mem.Allocator, *anyopaque) void;
```

<a id="type-allocatorlifetime"></a>

## AllocatorLifetime

Keeps allocator infrastructure alive while shared userdata outlives its State.
The last release, from any thread, destroys it.

```zig
pub const AllocatorLifetime = struct {
    references: std.atomic.Value(usize) = .init(1),
    destroy: *const fn (*AllocatorLifetime) void,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [retain](#fn-allocatorlifetime-retain) | `self: *AllocatorLifetime` | `void` |  |
| [release](#fn-allocatorlifetime-release) | `self: *AllocatorLifetime` | `void` |  |

<a id="fn-allocatorlifetime-retain"></a>

### AllocatorLifetime.retain

```zig
pub fn retain(self: *AllocatorLifetime) void
```

References: [`AllocatorLifetime`](#type-allocatorlifetime)

<a id="fn-allocatorlifetime-release"></a>

### AllocatorLifetime.release

```zig
pub fn release(self: *AllocatorLifetime) void
```

References: [`AllocatorLifetime`](#type-allocatorlifetime)

<a id="const-userdatasnapshotcopy"></a>

## UserdataSnapshotCopy

```zig
pub const UserdataSnapshotCopy = *const fn (std.mem.Allocator, *const anyopaque) anyerror!*anyopaque;
```

<a id="type-userdatapayload"></a>

## UserdataPayload

Payload ownership is separate from the GC-managed Lua wrapper.

```zig
pub const UserdataPayload = struct {
    allocator: std.mem.Allocator,
    lifetime: ?*AllocatorLifetime,
    references: std.atomic.Value(usize) = .init(1),
    ptr: *anyopaque,
    /// Inline storage owned by this payload; nested storage is accounted by the host allocator.
    managed_bytes: usize = 0,
    finalizer: ?UserdataFinalizer,
    finalizer_data: ?*const anyopaque,
    dispose: ?UserdataDeinit,
    finalized: bool = false,
    snapshot_copy: ?UserdataSnapshotCopy = null,
    snapshot_tracking: enum { eager, scoped } = .eager,
    snapshot_dispose: ?UserdataDeinit = null,
    is_snapshot_copy: bool = false,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [retain](#fn-userdatapayload-retain) | `self: *UserdataPayload` | `void` |  |
| [finalize](#fn-userdatapayload-finalize) | `self: *UserdataPayload` | `void` |  |
| [release](#fn-userdatapayload-release) | `self: *UserdataPayload, discard: bool` | `void` |  |

<a id="fn-userdatapayload-retain"></a>

### UserdataPayload.retain

```zig
pub fn retain(self: *UserdataPayload) void
```

References: [`UserdataPayload`](#type-userdatapayload)

<a id="fn-userdatapayload-finalize"></a>

### UserdataPayload.finalize

```zig
pub fn finalize(self: *UserdataPayload) void
```

References: [`UserdataPayload`](#type-userdatapayload)

<a id="fn-userdatapayload-release"></a>

### UserdataPayload.release

```zig
pub fn release(self: *UserdataPayload, discard: bool) void
```

References: [`UserdataPayload`](#type-userdatapayload)

<a id="type-protectedcallresult"></a>

## ProtectedCallResult

```zig
pub const ProtectedCallResult = union(enum) {
    success: []Value,
    failure: Value,
};
```

<a id="const-apicallbackdispatchfn"></a>

## ApiCallbackDispatchFn

```zig
pub const ApiCallbackDispatchFn = *const fn (*ApiCallbackContext) anyerror!void;
```

References: [`ApiCallbackContext`](#type-apicallbackcontext)

<a id="type-callbackreturns"></a>

## CallbackReturns

Stores small callback results inline, without self pointers. GC visits them through `items()`.

```zig
pub const CallbackReturns = struct {
    inline_values: [4]Value = undefined,
    inline_len: usize = 0,
    spill: std.ArrayList(Value) = .empty,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [items](#fn-callbackreturns-items) | `self: *const CallbackReturns` | `[]const Value` |  |
| [deinit](#fn-callbackreturns-deinit) | `self: *CallbackReturns, allocator: std.mem.Allocator` | `void` |  |
| [clearRetainingCapacity](#fn-callbackreturns-clearretainingcapacity) | `self: *CallbackReturns` | `void` |  |
| [append](#fn-callbackreturns-append) | `self: *CallbackReturns, allocator: std.mem.Allocator, value: Value` | `!void` |  |

<a id="fn-callbackreturns-items"></a>

### CallbackReturns.items

```zig
pub fn items(self: *const CallbackReturns) []const Value
```

References: [`CallbackReturns`](#type-callbackreturns), [`Value`](#type-value)

<a id="fn-callbackreturns-deinit"></a>

### CallbackReturns.deinit

```zig
pub fn deinit(self: *CallbackReturns, allocator: std.mem.Allocator) void
```

References: [`CallbackReturns`](#type-callbackreturns)

<a id="fn-callbackreturns-clearretainingcapacity"></a>

### CallbackReturns.clearRetainingCapacity

```zig
pub fn clearRetainingCapacity(self: *CallbackReturns) void
```

References: [`CallbackReturns`](#type-callbackreturns)

<a id="fn-callbackreturns-append"></a>

### CallbackReturns.append

```zig
pub fn append(self: *CallbackReturns, allocator: std.mem.Allocator, value: Value) !void
```

References: [`CallbackReturns`](#type-callbackreturns), [`Value`](#type-value)

<a id="type-apicallbackcontext"></a>

## ApiCallbackContext

```zig
pub const ApiCallbackContext = struct {
    state: *State,
    thread: *Thread,
    op: bytecode.Call,
    callback_id: usize,
    argument_base: usize,
    parent: ?*ApiCallbackContext,
    user_data: ?*anyopaque,
    function_name: []const u8 = "host callback",
    returns: CallbackReturns = .{},
    error_value: ?Value = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-apicallbackcontext-deinit) | `self: *ApiCallbackContext` | `void` |  |
| [argCount](#fn-apicallbackcontext-argcount) | `self: *ApiCallbackContext` | `usize` |  |
| [callbackArgValue](#fn-apicallbackcontext-callbackargvalue) | `self: *ApiCallbackContext, index: usize` | `Value` |  |
| [clearReturns](#fn-apicallbackcontext-clearreturns) | `self: *ApiCallbackContext` | `void` |  |
| [appendReturn](#fn-apicallbackcontext-appendreturn) | `self: *ApiCallbackContext, value: Value` | `!void` |  |
| [fail](#fn-apicallbackcontext-fail) | `self: *ApiCallbackContext, message: []const u8` | `RuntimeError` |  |
| [failArgumentMessage](#fn-apicallbackcontext-failargumentmessage) | `self: *ApiCallbackContext, index: usize, message: []const u8` | `RuntimeError` |  |
| [failArgumentType](#fn-apicallbackcontext-failargumenttype) | `self: *ApiCallbackContext, index: usize, expected: []const u8, actual: Value` | `RuntimeError` |  |
| [raise](#fn-apicallbackcontext-raise) | `self: *ApiCallbackContext, value: Value` | `error` |  |

<a id="fn-apicallbackcontext-deinit"></a>

### ApiCallbackContext.deinit

```zig
pub fn deinit(self: *ApiCallbackContext) void
```

References: [`ApiCallbackContext`](#type-apicallbackcontext)

<a id="fn-apicallbackcontext-argcount"></a>

### ApiCallbackContext.argCount

```zig
pub fn argCount(self: *ApiCallbackContext) usize
```

References: [`ApiCallbackContext`](#type-apicallbackcontext)

<a id="fn-apicallbackcontext-callbackargvalue"></a>

### ApiCallbackContext.callbackArgValue

```zig
pub fn callbackArgValue(self: *ApiCallbackContext, index: usize) Value
```

References: [`ApiCallbackContext`](#type-apicallbackcontext), [`Value`](#type-value)

<a id="fn-apicallbackcontext-clearreturns"></a>

### ApiCallbackContext.clearReturns

```zig
pub fn clearReturns(self: *ApiCallbackContext) void
```

References: [`ApiCallbackContext`](#type-apicallbackcontext)

<a id="fn-apicallbackcontext-appendreturn"></a>

### ApiCallbackContext.appendReturn

```zig
pub fn appendReturn(self: *ApiCallbackContext, value: Value) !void
```

References: [`ApiCallbackContext`](#type-apicallbackcontext), [`Value`](#type-value)

<a id="fn-apicallbackcontext-fail"></a>

### ApiCallbackContext.fail

```zig
pub fn fail(self: *ApiCallbackContext, message: []const u8) RuntimeError
```

References: [`ApiCallbackContext`](#type-apicallbackcontext), [`RuntimeError`](#type-runtimeerror)

<a id="fn-apicallbackcontext-failargumentmessage"></a>

### ApiCallbackContext.failArgumentMessage

```zig
pub fn failArgumentMessage(self: *ApiCallbackContext, index: usize, message: []const u8) RuntimeError
```

References: [`ApiCallbackContext`](#type-apicallbackcontext), [`RuntimeError`](#type-runtimeerror)

<a id="fn-apicallbackcontext-failargumenttype"></a>

### ApiCallbackContext.failArgumentType

```zig
pub fn failArgumentType(self: *ApiCallbackContext, index: usize, expected: []const u8, actual: Value) RuntimeError
```

References: [`ApiCallbackContext`](#type-apicallbackcontext), [`Value`](#type-value), [`RuntimeError`](#type-runtimeerror)

<a id="fn-apicallbackcontext-raise"></a>

### ApiCallbackContext.raise

```zig
pub fn raise(self: *ApiCallbackContext, value: Value) error{LuaError}
```

References: [`ApiCallbackContext`](#type-apicallbackcontext), [`Value`](#type-value)

<a id="type-runtimeerrorpayload"></a>

## RuntimeErrorPayload

```zig
pub const RuntimeErrorPayload = union(enum) {
    /// Process-lifetime text.
    diagnostic: []const u8,
    lua_value: Value,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [luaValue](#fn-runtimeerrorpayload-luavalue) | `self: RuntimeErrorPayload, state: anytype` | `Value` |  |

<a id="fn-runtimeerrorpayload-luavalue"></a>

### RuntimeErrorPayload.luaValue

```zig
pub fn luaValue(self: RuntimeErrorPayload, state: anytype) Value
```

References: [`RuntimeErrorPayload`](#type-runtimeerrorpayload), [`Value`](#type-value)

<a id="type-protectedcallcontext"></a>

## ProtectedCallContext

```zig
pub const ProtectedCallContext = struct {
    frame_count: usize,
    relative_base: u32,
    absolute_base: usize,
    stack_len: usize,
    last_result_base: usize,
    last_result_count: usize,
    last_error: ?RuntimeErrorPayload,
    /// Message handler installed for the call, like `lua_pcall`'s `msgh`.
    error_handler: Value = .nil,
    /// The thread's handler before the call, restored when it ends.
    previous_error_handler: Value = .nil,
};
```

<a id="type-nativemark"></a>

## NativeMark

```zig
pub const NativeMark = struct {
    /// Frame count when the native function was called.
    frame_count: u32,
    callee: Value,
};
```

<a id="type-protectedcontinuation"></a>

## ProtectedContinuation

```zig
pub const ProtectedContinuation = struct {
    order: usize,
    context: ProtectedCallContext,
    base: u32,
    return_count: u16,
};
```

<a id="type-genericforcontinuation"></a>

## GenericForContinuation

```zig
pub const GenericForContinuation = struct {
    frame_count: usize,
    op: bytecode.GenericFor,
    jump_on_nil: bool,
};
```

<a id="type-pairscontinuation"></a>

## PairsContinuation

```zig
pub const PairsContinuation = struct {
    order: usize = 0,
    frame_count: usize,
    source_base: usize,
    base: u32,
    return_count: u16,
};
```

<a id="type-branchcontinuation"></a>

## BranchContinuation

```zig
pub const BranchContinuation = struct {
    jump_if_truthy: bool,
    offset: bytecode.JumpOffset,
};
```

<a id="type-tailcallcontinuation"></a>

## TailCallContinuation

```zig
pub const TailCallContinuation = struct {
    frame_count: usize,
    base: u32,
    return_count: u16,
};
```

<a id="type-callonecontinuationresult"></a>

## CallOneContinuationResult

```zig
pub const CallOneContinuationResult = union(enum) {
    value: usize,
    truthy: usize,
    inverted_truthy: usize,
    branch_truthy: BranchContinuation,
    branch_inverted_truthy: BranchContinuation,
    concat: ConcatContinuation,
    discard,
};
```

<a id="type-concatcontinuation"></a>

## ConcatContinuation

A `concat_range` suspended in `__concat`. Slots are absolute stack indices; the
metamethod result becomes the last of the `count` operands starting at `first`.

```zig
pub const ConcatContinuation = struct {
    dest: usize,
    first: usize,
    count: usize,
};
```

<a id="type-callonecontinuation"></a>

## CallOneContinuation

```zig
pub const CallOneContinuation = struct {
    frame_count: usize,
    result: CallOneContinuationResult,
};
```

<a id="type-coroutineresumeresult"></a>

## CoroutineResumeResult

```zig
pub const CoroutineResumeResult = union(enum) {
    success: []Value,
    failure: Value,
};
```

<a id="type-chunk"></a>

## Chunk

A loaded prototype tree's constants in one State, with its strings interned there.

```zig
pub const Chunk = struct {
    root: *proto_mod.Proto,
    root_owner: RootOwner,
    /// Collector epoch of the last mark.
    epoch: u32 = 0,
    /// Each prototype's constants, starting at its `constant_offset`.
    values: []Value,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [RootOwner](#type-chunk-rootowner) |  |  |  |
| [allocationBytes](#fn-chunk-allocationbytes) | `self: *const Chunk` | `usize` |  |
| [destroy](#fn-chunk-destroy) | `self: *Chunk, allocator: std.mem.Allocator` | `void` |  |

<a id="type-chunk-rootowner"></a>

### Chunk.RootOwner

```zig
pub const RootOwner = enum {
    /// Freed with the chunk.
    state,
    /// Shared with the snapshot this State was created from.
    snapshot,
    /// Owned by the host that executed it.
    host,
};
```

<a id="fn-chunk-allocationbytes"></a>

### Chunk.allocationBytes

```zig
pub fn allocationBytes(self: *const Chunk) usize
```

References: [`Chunk`](#type-chunk)

<a id="fn-chunk-destroy"></a>

### Chunk.destroy

```zig
pub fn destroy(self: *Chunk, allocator: std.mem.Allocator) void
```

References: [`Chunk`](#type-chunk)

<a id="type-closure"></a>

## Closure

A Lua function, followed by its `upvalue_count` upvalue pointers in the same allocation.

```zig
pub const Closure = struct {
    gc: GcHeader = .{},
    rollback: ?*@import("rollback.zig").Record(Closure) = null,
    proto: *const proto_mod.Proto,
    /// Null for host frames.
    chunk: ?*Chunk = null,
    upvalue_count: u32 = 0,
    stripped_debug: bool = false,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [constants](#fn-closure-constants) | `self: *const Closure` | `[*]const Value` |  |
| [upvalues](#fn-closure-upvalues) | `self: *const Closure` | `[]*Upvalue` |  |
| [allocationBytes](#fn-closure-allocationbytes) | `upvalue_count: usize` | `usize` |  |
| [create](#fn-closure-create) | `allocator: std.mem.Allocator, upvalue_count: usize, initial: Closure` | `!*Closure` | Allocates &#96;initial&#96; with room for &#96;upvalue_count&#96; upvalues, which start undefined. |
| [destroy](#fn-closure-destroy) | `allocator: std.mem.Allocator, closure: *Closure` | `void` |  |

<a id="fn-closure-constants"></a>

### Closure.constants

```zig
pub inline fn constants(self: *const Closure) [*]const Value
```

References: [`Closure`](#type-closure), [`Value`](#type-value)

<a id="fn-closure-upvalues"></a>

### Closure.upvalues

```zig
pub inline fn upvalues(self: *const Closure) []*Upvalue
```

References: [`Closure`](#type-closure), [`Upvalue`](#type-upvalue)

<a id="fn-closure-allocationbytes"></a>

### Closure.allocationBytes

```zig
pub fn allocationBytes(upvalue_count: usize) usize
```

<a id="fn-closure-create"></a>

### Closure.create

Allocates `initial` with room for `upvalue_count` upvalues, which start undefined.

```zig
pub fn create(allocator: std.mem.Allocator, upvalue_count: usize, initial: Closure) !*Closure
```

References: [`Closure`](#type-closure)

<a id="fn-closure-destroy"></a>

### Closure.destroy

```zig
pub fn destroy(allocator: std.mem.Allocator, closure: *Closure) void
```

References: [`Closure`](#type-closure)

<a id="type-upvalue"></a>

## Upvalue

```zig
pub const Upvalue = struct {
    gc: GcHeader = .{},
    rollback: ?*@import("rollback.zig").Record(Upvalue) = null,
    /// Next open upvalue of the owner thread.
    next: ?*Upvalue = null,
    cell: Cell,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Cell](#type-upvalue-cell) |  |  |  |
| [Slot](#type-upvalue-slot) |  |  | The owner thread's stack slot that an open upvalue refers to. |
| [get](#fn-upvalue-get) | `self: *const Upvalue` | `Value` |  |

<a id="type-upvalue-cell"></a>

### Upvalue.Cell

```zig
pub const Cell = union(enum) {
    open: Slot,
    closed: Value,
};
```

<a id="type-upvalue-slot"></a>

### Upvalue.Slot

The owner thread's stack slot that an open upvalue refers to.

```zig
pub const Slot = struct {
    owner: *Thread,
    stack_index: usize,
};
```

<a id="fn-upvalue-get"></a>

### Upvalue.get

```zig
pub inline fn get(self: *const Upvalue) Value
```

References: [`Upvalue`](#type-upvalue), [`Value`](#type-value)

<a id="type-tableentry"></a>

## TableEntry

```zig
pub const TableEntry = struct {
    key: Value,
    value: Value,
};
```

<a id="alias-tablehashpart"></a>

## TableHashPart

```zig
pub const TableHashPart = table_index.HashPart;
```

<a id="type-metaevent"></a>

## MetaEvent

Metamethod events whose absence a metatable caches in
`Table.metamethod_absent`. [Tag](../frontend/token.md#type-tag) names are the event keys.

```zig
pub const MetaEvent = enum(u5) {
    __index,
    __newindex,
    __len,
    __eq,
    __call,
    __add,
    __sub,
    __mul,
    __div,
    __mod,
    __pow,
    __unm,
    __idiv,
    __band,
    __bor,
    __bxor,
    __shl,
    __shr,
    __bnot,
    __lt,
    __le,
    __concat,
    __close,
    __tostring,
    __name,
    __pairs,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [fromName](#fn-metaevent-fromname) | `name: []const u8` | `?MetaEvent` |  |

<a id="fn-metaevent-fromname"></a>

### MetaEvent.fromName

```zig
pub fn fromName(name: []const u8) ?MetaEvent
```

References: [`MetaEvent`](#type-metaevent)

<a id="type-tablearray"></a>

## TableArray

A table's array part.

```zig
pub const TableArray = struct {
    ptr: [*]Value = empty_ptr,
    len: u32 = 0,
    capacity: u32 = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [items](#fn-tablearray-items) | `self: TableArray` | `[]Value` |  |
| [allocatedSlice](#fn-tablearray-allocatedslice) | `self: TableArray` | `[]Value` |  |
| [ensureTotalCapacityPrecise](#fn-tablearray-ensuretotalcapacityprecise) | `self: *TableArray, allocator: std.mem.Allocator, capacity: usize` | `!void` |  |
| [resize](#fn-tablearray-resize) | `self: *TableArray, allocator: std.mem.Allocator, new_len: usize` | `!void` | New elements are undefined. |
| [appendAssumeCapacity](#fn-tablearray-appendassumecapacity) | `self: *TableArray, value: Value` | `void` |  |
| [clone](#fn-tablearray-clone) | `self: TableArray, allocator: std.mem.Allocator` | `!TableArray` | A copy with the same capacity. |
| [deinit](#fn-tablearray-deinit) | `self: *TableArray, allocator: std.mem.Allocator` | `void` |  |

<a id="fn-tablearray-items"></a>

### TableArray.items

```zig
pub inline fn items(self: TableArray) []Value
```

References: [`TableArray`](#type-tablearray), [`Value`](#type-value)

<a id="fn-tablearray-allocatedslice"></a>

### TableArray.allocatedSlice

```zig
pub inline fn allocatedSlice(self: TableArray) []Value
```

References: [`TableArray`](#type-tablearray), [`Value`](#type-value)

<a id="fn-tablearray-ensuretotalcapacityprecise"></a>

### TableArray.ensureTotalCapacityPrecise

```zig
pub fn ensureTotalCapacityPrecise(self: *TableArray, allocator: std.mem.Allocator, capacity: usize) !void
```

References: [`TableArray`](#type-tablearray)

<a id="fn-tablearray-resize"></a>

### TableArray.resize

New elements are undefined.

```zig
pub fn resize(self: *TableArray, allocator: std.mem.Allocator, new_len: usize) !void
```

References: [`TableArray`](#type-tablearray)

<a id="fn-tablearray-appendassumecapacity"></a>

### TableArray.appendAssumeCapacity

```zig
pub inline fn appendAssumeCapacity(self: *TableArray, value: Value) void
```

References: [`TableArray`](#type-tablearray), [`Value`](#type-value)

<a id="fn-tablearray-clone"></a>

### TableArray.clone

A copy with the same capacity.

```zig
pub fn clone(self: TableArray, allocator: std.mem.Allocator) !TableArray
```

References: [`TableArray`](#type-tablearray)

<a id="fn-tablearray-deinit"></a>

### TableArray.deinit

```zig
pub fn deinit(self: *TableArray, allocator: std.mem.Allocator) void
```

References: [`TableArray`](#type-tablearray)

<a id="type-table"></a>

## Table

```zig
pub const Table = struct {
    gc: GcHeader = .{},
    rollback: ?*@import("rollback.zig").Record(Table) = null,
    array: TableArray = .{},
    hash: ?*TableHashPart = null,
    metatable: ?*Table = null,
    /// Has been some table's metatable.
    used_as_metatable: bool = false,
    /// In `State.table_finalizers` or `State.table_pending_finalizers`.
    finalizer_registered: bool = false,
    /// Bit `e` set: this metatable has no raw value for `MetaEvent` `e`. Hash-part
    /// writes that may turn nil into non-nil clear the whole set.
    metamethod_absent: u32 = 0,
    /// In `Gc.weak`.
    in_weak_list: bool = false,
    /// In `Gc.tables`.
    in_table_list: bool = false,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [init](#fn-table-init) | `allocator: std.mem.Allocator, array_hint: u32, hash_hint: u32` | `!Table` |  |
| [deinit](#fn-table-deinit) | `self: *Table, allocator: std.mem.Allocator` | `void` |  |
| [reserveArray](#fn-table-reservearray) | `self: *Table, allocator: std.mem.Allocator, count: usize` | `!void` |  |
| [reserveEntries](#fn-table-reserveentries) | `self: *Table, allocator: std.mem.Allocator, count: usize` | `!void` |  |
| [entries](#fn-table-entries) | `self: *const Table` | `[]TableEntry` |  |
| [entryCapacity](#fn-table-entrycapacity) | `self: *const Table` | `usize` |  |
| [truncateEntries](#fn-table-truncateentries) | `self: *Table, count: usize` | `void` | &#96;count&#96; must not exceed the current number of entries. |
| [appendEntriesAssumeCapacity](#fn-table-appendentriesassumecapacity) | `self: *Table, new_entries: []const TableEntry` | `void` | The keys must be distinct and absent, and capacity reserved. |
| [get](#fn-table-get) | `self: *const Table, key: Value` | `Value` |  |
| [getStringHashed](#fn-table-getstringhashed) | `self: *const Table, key: []const u8, hash: u32` | `Value` | Raw read of a string key whose &#96;table_index.hashStringKey&#96; the caller already knows. |
| [getString](#fn-table-getstring) | `self: *const Table, key: *const String` | `Value` |  |
| [getLiteral](#fn-table-getliteral) | `self: *const Table, comptime key: []const u8` | `Value` |  |
| [getBytes](#fn-table-getbytes) | `self: *const Table, key: []const u8` | `Value` |  |
| [findStringEntry](#fn-table-findstringentry) | `self: *const Table, key: []const u8, hash: u32` | `?usize` |  |
| [findStringKey](#fn-table-findstringkey) | `self: *const Table, key: *const String` | `?usize` |  |
| [metaEventAbsent](#fn-table-metaeventabsent) | `self: *const Table, event: MetaEvent` | `bool` |  |
| [metaEvent](#fn-table-metaevent) | `self: *Table, event: MetaEvent` | `Value` | Raw lookup of a metamethod in this metatable, caching absence. |
| [invalidateMetaEvents](#fn-table-invalidatemetaevents) | `self: *Table` | `void` | Call before writing a hash slot that may currently hold nil. |
| [findEntry](#fn-table-findentry) | `self: *const Table, key: Value` | `?usize` |  |
| [insertHashEntryNoAlloc](#fn-table-inserthashentrynoalloc) | `self: *Table, key: Value, value: Value` | `bool` | Insert an absent hash key using reserved storage. The caller must check that the key is absent; false means growth or snapshot detachment is needed. |
| [set](#fn-table-set) | `self: *Table, allocator: std.mem.Allocator, key: Value, value: Value` | `!void` |  |
| [setExistingNonNil](#fn-table-setexistingnonnil) | `self: *Table, key: Value, value: Value` | `bool` |  |
| [len](#fn-table-len) | `self: *Table` | `i64` |  |
| [next](#fn-table-next) | `self: *const Table, key: Value` | `![2]Value` |  |
| [removeHashKey](#fn-table-removehashkey) | `self: *Table, key: Value` | `void` |  |
| [removeEntryAt](#fn-table-removeentryat) | `self: *Table, index: usize` | `void` | Removes one entry, keeping the order of the rest for &#96;next&#96;. |

<a id="fn-table-init"></a>

### Table.init

```zig
pub inline fn init(allocator: std.mem.Allocator, array_hint: u32, hash_hint: u32) !Table
```

References: [`Table`](#type-table)

<a id="fn-table-deinit"></a>

### Table.deinit

```zig
pub fn deinit(self: *Table, allocator: std.mem.Allocator) void
```

References: [`Table`](#type-table)

<a id="fn-table-reservearray"></a>

### Table.reserveArray

```zig
pub inline fn reserveArray(self: *Table, allocator: std.mem.Allocator, count: usize) !void
```

References: [`Table`](#type-table)

<a id="fn-table-reserveentries"></a>

### Table.reserveEntries

```zig
pub inline fn reserveEntries(self: *Table, allocator: std.mem.Allocator, count: usize) !void
```

References: [`Table`](#type-table)

<a id="fn-table-entries"></a>

### Table.entries

```zig
pub inline fn entries(self: *const Table) []TableEntry
```

References: [`Table`](#type-table), [`TableEntry`](#type-tableentry)

<a id="fn-table-entrycapacity"></a>

### Table.entryCapacity

```zig
pub inline fn entryCapacity(self: *const Table) usize
```

References: [`Table`](#type-table)

<a id="fn-table-truncateentries"></a>

### Table.truncateEntries

`count` must not exceed the current number of entries.

```zig
pub fn truncateEntries(self: *Table, count: usize) void
```

References: [`Table`](#type-table)

<a id="fn-table-appendentriesassumecapacity"></a>

### Table.appendEntriesAssumeCapacity

The keys must be distinct and absent, and capacity reserved.

```zig
pub fn appendEntriesAssumeCapacity(self: *Table, new_entries: []const TableEntry) void
```

References: [`Table`](#type-table), [`TableEntry`](#type-tableentry)

<a id="fn-table-get"></a>

### Table.get

```zig
pub fn get(self: *const Table, key: Value) Value
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-getstringhashed"></a>

### Table.getStringHashed

Raw read of a string key whose `table_index.hashStringKey` the caller already knows.

```zig
pub inline fn getStringHashed(self: *const Table, key: []const u8, hash: u32) Value
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-getstring"></a>

### Table.getString

```zig
pub inline fn getString(self: *const Table, key: *const String) Value
```

References: [`Table`](#type-table), [`String`](#type-string), [`Value`](#type-value)

<a id="fn-table-getliteral"></a>

### Table.getLiteral

```zig
pub inline fn getLiteral(self: *const Table, comptime key: []const u8) Value
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-getbytes"></a>

### Table.getBytes

```zig
pub fn getBytes(self: *const Table, key: []const u8) Value
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-findstringentry"></a>

### Table.findStringEntry

```zig
pub inline fn findStringEntry(self: *const Table, key: []const u8, hash: u32) ?usize
```

References: [`Table`](#type-table)

<a id="fn-table-findstringkey"></a>

### Table.findStringKey

```zig
pub inline fn findStringKey(self: *const Table, key: *const String) ?usize
```

References: [`Table`](#type-table), [`String`](#type-string)

<a id="fn-table-metaeventabsent"></a>

### Table.metaEventAbsent

```zig
pub inline fn metaEventAbsent(self: *const Table, event: MetaEvent) bool
```

References: [`Table`](#type-table), [`MetaEvent`](#type-metaevent)

<a id="fn-table-metaevent"></a>

### Table.metaEvent

Raw lookup of a metamethod in this metatable, caching absence.

```zig
pub fn metaEvent(self: *Table, event: MetaEvent) Value
```

References: [`Table`](#type-table), [`MetaEvent`](#type-metaevent), [`Value`](#type-value)

<a id="fn-table-invalidatemetaevents"></a>

### Table.invalidateMetaEvents

[Call](../compile/bytecode.md#type-call) before writing a hash slot that may currently hold nil.

```zig
pub inline fn invalidateMetaEvents(self: *Table) void
```

References: [`Table`](#type-table)

<a id="fn-table-findentry"></a>

### Table.findEntry

```zig
pub fn findEntry(self: *const Table, key: Value) ?usize
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-inserthashentrynoalloc"></a>

### Table.insertHashEntryNoAlloc

Insert an absent hash key using reserved storage. The caller must check
that the key is absent; false means growth or snapshot detachment is needed.

```zig
pub fn insertHashEntryNoAlloc(self: *Table, key: Value, value: Value) bool
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-set"></a>

### Table.set

```zig
pub fn set(self: *Table, allocator: std.mem.Allocator, key: Value, value: Value) !void
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-setexistingnonnil"></a>

### Table.setExistingNonNil

```zig
pub fn setExistingNonNil(self: *Table, key: Value, value: Value) bool
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-len"></a>

### Table.len

```zig
pub fn len(self: *Table) i64
```

References: [`Table`](#type-table)

<a id="fn-table-next"></a>

### Table.next

```zig
pub fn next(self: *const Table, key: Value) ![2]Value
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-removehashkey"></a>

### Table.removeHashKey

```zig
pub fn removeHashKey(self: *Table, key: Value) void
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-removeentryat"></a>

### Table.removeEntryAt

Removes one entry, keeping the order of the rest for `next`.

```zig
pub fn removeEntryAt(self: *Table, index: usize) void
```

References: [`Table`](#type-table)

<a id="type-userdatascope"></a>

## UserdataScope

```zig
pub const UserdataScope = struct {
    userdata: *Userdata,
    readonly: bool,
    previous: ?*UserdataScope,
};
```

<a id="type-valueroots"></a>

## ValueRoots

Values a native function holds outside the Lua stack while it runs Lua
code. The collector marks them until the scope is popped.

```zig
pub const ValueRoots = struct {
    values: []const Value,
    previous: ?*ValueRoots,
};
```

<a id="type-userdata"></a>

## Userdata

```zig
pub const Userdata = struct {
    gc: GcHeader = .{},
    scope_readers: usize = 0,
    scope_writers: usize = 0,
    rollback: ?*@import("rollback.zig").Record(Userdata) = null,
    payload: ?*UserdataPayload = null,
    ptr: *anyopaque,
    type_id: usize,
    type_name: []const u8,
    metatable: ?*Table = null,
    finalizer: ?UserdataFinalizer = null,
    finalizer_data: ?*const anyopaque = null,
    deinit_fn: ?UserdataDeinit = null,
    finalized: bool = false,
    finalization_pending: bool = false,
    finalizer_next: ?*Userdata = null,
    /// Registered for its metatable's `__gc`, like `Table.finalizer_registered`.
    lua_finalizer_registered: bool = false,
    /// Registration order on the `TableFinalizer.order` scale, then the
    /// position in the finalizer queue once separated.
    lua_finalizer_order: u64 = 0,
    lua_finalizer_next: ?*Userdata = null,
};
```

<a id="type-tablefinalizer"></a>

## TableFinalizer

A table registered for a Lua `__gc`, with its order on the finalizer scale.

```zig
pub const TableFinalizer = struct {
    table: *Table,
    order: u64,
};
```

<a id="type-finalizerobject"></a>

## FinalizerObject

An object separated for a Lua `__gc` call.

```zig
pub const FinalizerObject = union(enum) {
    table: TableFinalizer,
    userdata: *Userdata,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [order](#fn-finalizerobject-order) | `self: FinalizerObject` | `u64` |  |

<a id="fn-finalizerobject-order"></a>

### FinalizerObject.order

```zig
pub fn order(self: FinalizerObject) u64
```

References: [`FinalizerObject`](#type-finalizerobject)

<a id="type-thread"></a>

## Thread

```zig
pub const Thread = struct {
    gc: GcHeader = .{},
    rollback: ?*@import("rollback.zig").Record(Thread) = null,
    /// A Lua value has exposed this thread beyond its current host call.
    exposed: bool = false,
    stack: std.ArrayList(Value) = .empty,
    frames: std.ArrayList(CallFrame) = .empty,
    /// Extra state of the frames with `has_extra`, at their frame index.
    frame_extras: std.ArrayList(FrameExtra) = .empty,
    yield_values: std.ArrayList(Value) = .empty,
    protected_continuations: std.ArrayList(ProtectedContinuation) = .empty,
    generic_for_continuations: std.ArrayList(GenericForContinuation) = .empty,
    pairs_continuations: std.ArrayList(PairsContinuation) = .empty,
    continuation_order: usize = 0,
    tail_call_continuations: std.ArrayList(TailCallContinuation) = .empty,
    call_one_continuations: std.ArrayList(CallOneContinuation) = .empty,
    /// Largest `frame_count` among the pending continuations. Every push calls
    /// `noteContinuation`; every removal calls `refreshContinuationFrameCount`.
    continuation_frame_count: usize = 0,
    open_upvalues: ?*Upvalue = null,
    hook: Value = .nil,
    hook_call: bool = false,
    hook_line: bool = false,
    hook_return: bool = false,
    hook_count: u32 = 0,
    hook_count_remaining: u32 = 0,
    hook_running: bool = false,
    hook_return_name: ?[]const u8 = null,
    hook_level2_func: Value = .nil,
    hook_transfer_index_base: i64 = 0,
    hook_transfer_stack_base: usize = 0,
    hook_transfer_count: usize = 0,
    hook_transfer_values: []const Value = &.{},
    next_call_name: ?[]const u8 = null,
    next_call_namewhat: ?[]const u8 = null,
    pending_yield_hook_return: bool = false,
    last_result_base: usize = 0,
    last_result_count: usize = 0,
    last_transfer_base: usize = 0,
    last_transfer_count: usize = 0,
    yield_result_base: usize = 0,
    yield_result_count: u16 = 0,
    native_call_depth: usize = 0,
    native_call: ?NativeCall = null,
    protected_close_depth: usize = 0,
    /// Message handler for errors raised on this thread, like `L->errfunc`.
    error_handler: Value = .nil,
    /// Set after a stack overflow so a message handler can still run on top
    /// of the full stack; cleared once the stack unwinds below the limit.
    stack_error_space: bool = false,
    /// Tracebacks end with the `[C]: in ?` entry of a standalone host call.
    host_frame: bool = false,
    /// Native functions with no calling instruction (called by `xpcall` or a message
    /// handler) still live while a message handler runs, oldest first, for tracebacks.
    native_marks: [4]NativeMark = undefined,
    native_mark_count: u8 = 0,
    close_error_value: ?Value = null,
    error_traceback: ?*const String = null,
    pending_unwind_error: ?Value = null,
    pending_unwind_resume_frame_count: usize = 0,
    pending_unwind_target_frame_count: usize = 0,
    /// Bytes of pending returns held by this thread's frames.
    frame_storage_bytes: usize = 0,
    /// Capacity bytes last reported to the collector.
    storage_bytes: usize = 0,
    resume_parent: ?*Thread = null,
    entry: Value = .nil,
    started: bool = false,
    is_main: bool = false,
    closing: bool = false,
    status: ThreadStatus = .suspended,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [initRoot](#fn-thread-initroot) | `allocator: std.mem.Allocator, closure: *Closure, stack_value_limit: usize` | `!Thread` |  |
| [initCoroutine](#fn-thread-initcoroutine) | `entry: Value` | `Thread` |  |
| [deinit](#fn-thread-deinit) | `self: *Thread, allocator: std.mem.Allocator` | `void` |  |
| [releaseFrame](#fn-thread-releaseframe) | `self: *Thread, index: usize, allocator: std.mem.Allocator` | `void` | Frees the extra state of frame &#96;index&#96;, which stays on the frame list. |
| [frameExtra](#fn-thread-frameextra) | `self: *const Thread, index: usize` | `FrameExtra` | The extra state of frame &#96;index&#96;, or defaults when it has none. |
| [frameExtraMut](#fn-thread-frameextramut) | `self: *Thread, allocator: std.mem.Allocator, index: usize` | `!*FrameExtra` | The extra state of frame &#96;index&#96;, created on first use. |
| [clearHookLine](#fn-thread-clearhookline) | `self: *Thread, index: usize` | `void` |  |
| [noteContinuation](#fn-thread-notecontinuation) | `self: *Thread, frame_count: usize` | `void` |  |
| [refreshContinuationFrameCount](#fn-thread-refreshcontinuationframecount) | `self: *Thread` | `void` |  |
| [ensureStack](#fn-thread-ensurestack) | `self: *Thread, allocator: std.mem.Allocator, size: usize, limit: usize` | `!void` |  |
| [scratchRegister](#fn-thread-scratchregister) | `self: *const Thread` | `u32` | Register, relative to the top frame, for calls the runtime makes itself: above the frame's registers and any running native function's arguments. |

<a id="fn-thread-initroot"></a>

### Thread.initRoot

```zig
pub fn initRoot(allocator: std.mem.Allocator, closure: *Closure, stack_value_limit: usize) !Thread
```

References: [`Closure`](#type-closure), [`Thread`](#type-thread)

<a id="fn-thread-initcoroutine"></a>

### Thread.initCoroutine

```zig
pub fn initCoroutine(entry: Value) Thread
```

References: [`Value`](#type-value), [`Thread`](#type-thread)

<a id="fn-thread-deinit"></a>

### Thread.deinit

```zig
pub fn deinit(self: *Thread, allocator: std.mem.Allocator) void
```

References: [`Thread`](#type-thread)

<a id="fn-thread-releaseframe"></a>

### Thread.releaseFrame

Frees the extra state of frame `index`, which stays on the frame list.

```zig
pub fn releaseFrame(self: *Thread, index: usize, allocator: std.mem.Allocator) void
```

References: [`Thread`](#type-thread)

<a id="fn-thread-frameextra"></a>

### Thread.frameExtra

The extra state of frame `index`, or defaults when it has none.

```zig
pub fn frameExtra(self: *const Thread, index: usize) FrameExtra
```

References: [`Thread`](#type-thread), [`FrameExtra`](#type-frameextra)

<a id="fn-thread-frameextramut"></a>

### Thread.frameExtraMut

The extra state of frame `index`, created on first use.

```zig
pub fn frameExtraMut(self: *Thread, allocator: std.mem.Allocator, index: usize) !*FrameExtra
```

References: [`Thread`](#type-thread), [`FrameExtra`](#type-frameextra)

<a id="fn-thread-clearhookline"></a>

### Thread.clearHookLine

```zig
pub inline fn clearHookLine(self: *Thread, index: usize) void
```

References: [`Thread`](#type-thread)

<a id="fn-thread-notecontinuation"></a>

### Thread.noteContinuation

```zig
pub fn noteContinuation(self: *Thread, frame_count: usize) void
```

References: [`Thread`](#type-thread)

<a id="fn-thread-refreshcontinuationframecount"></a>

### Thread.refreshContinuationFrameCount

```zig
pub fn refreshContinuationFrameCount(self: *Thread) void
```

References: [`Thread`](#type-thread)

<a id="fn-thread-ensurestack"></a>

### Thread.ensureStack

```zig
pub fn ensureStack(self: *Thread, allocator: std.mem.Allocator, size: usize, limit: usize) !void
```

References: [`Thread`](#type-thread)

<a id="fn-thread-scratchregister"></a>

### Thread.scratchRegister

[Register](../compile/bytecode.md#alias-register), relative to the top frame, for calls the runtime makes itself: above
the frame's registers and any running native function's arguments.

```zig
pub fn scratchRegister(self: *const Thread) u32
```

References: [`Thread`](#type-thread)

<a id="type-threadstatus"></a>

## ThreadStatus

```zig
pub const ThreadStatus = enum {
    suspended,
    running,
    normal,
    dead,
};
```

<a id="type-nativecall"></a>

## NativeCall

The innermost native function running on a thread. Library errors use it like
`luaL_argerror` and `luaL_where` use the C call stack.

```zig
pub const NativeCall = struct {
    /// Callee register, relative to the frame on top when it was called.
    base: u32,
    arg_count: u32,
    /// Arguments prepended by `__call` metamethods, like `lua_Debug.extraargs`.
    extra_args: u8 = 0,
    frame_count: usize,
    /// Called by another native function (like `pcall(f)`) rather than Lua code.
    from_native: bool,
    /// Frame count of the enclosing native call, if any.
    outer_frame_count: ?usize = null,
    /// Static name for calls not made by CALL instructions, such as metamethods and `__close`.
    name: ?[]const u8 = null,
    namewhat: ?[]const u8 = null,
};
```

<a id="type-callframe"></a>

## CallFrame

```zig
pub const CallFrame = struct {
    closure: *Closure,
    base: u32,
    pc: u32,
    return_start: u32,
    /// Stack index of the first extra argument, which sits below `base`.
    vararg_base: u32 = 0,
    vararg_count: u32 = 0,
    return_count: u16,
    named_vararg_readonly: bool = false,
    is_tail_call: bool = false,
    /// `Thread.frame_extras` holds this frame's `FrameExtra` at the same index.
    has_extra: bool = false,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [argumentBase](#fn-callframe-argumentbase) | `self: CallFrame` | `usize` | Stack index of the first argument the frame was called with. |
| [varargs](#fn-callframe-varargs) | `self: CallFrame, stack: []const Value` | `[]const Value` |  |

<a id="fn-callframe-argumentbase"></a>

### CallFrame.argumentBase

Stack index of the first argument the frame was called with.

```zig
pub fn argumentBase(self: CallFrame) usize
```

References: [`CallFrame`](#type-callframe)

<a id="fn-callframe-varargs"></a>

### CallFrame.varargs

```zig
pub fn varargs(self: CallFrame, stack: []const Value) []const Value
```

References: [`CallFrame`](#type-callframe), [`Value`](#type-value)

<a id="type-frameextra"></a>

## FrameExtra

Rarely set state of a call frame.

```zig
pub const FrameExtra = struct {
    debug_name_override: ?[]const u8 = null,
    debug_namewhat_override: ?[]const u8 = null,
    last_hook_line: ?usize = null,
    pending_returns: ?[]Value = null,
    vararg_table_local: Value = .nil,
};
```

<a id="type-addresscontext"></a>

## AddressContext

Hashes object addresses, which are distinct and aligned, without Wyhash.

```zig
pub const AddressContext = struct { ... };
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [hash](#fn-addresscontext-hash) | `_: AddressContext, address: usize` | `u64` |  |
| [eql](#fn-addresscontext-eql) | `_: AddressContext, lhs: usize, rhs: usize` | `bool` |  |

<a id="fn-addresscontext-hash"></a>

### AddressContext.hash

```zig
pub fn hash(_: AddressContext, address: usize) u64
```

References: [`AddressContext`](#type-addresscontext)

<a id="fn-addresscontext-eql"></a>

### AddressContext.eql

```zig
pub fn eql(_: AddressContext, lhs: usize, rhs: usize) bool
```

References: [`AddressContext`](#type-addresscontext)

<a id="type-gccolor"></a>

## GcColor

```zig
pub const GcColor = enum(u8) {
    white,
    gray,
    black,
};
```

<a id="type-gcage"></a>

## GcAge

```zig
pub const GcAge = enum(u8) {
    new,
    survivor,
    old,
};
```

<a id="type-gcheader"></a>

## GcHeader

Collector state embedded in every collectable object.

```zig
pub const GcHeader = extern struct {
    /// Collector epoch of the last mark; `color` is stale when it differs.
    epoch: u32 = 0,
    /// Collector generation at allocation; any older generation means old.
    generation: u32 = 0,
    /// Position in this type's registry; `untracked` for strings and objects the collector doesn't own.
    registry_index: u32 = untracked,
    color: GcColor = .white,
    age: GcAge = .new,
    /// In `Gc.remembered`.
    remembered: bool = false,
    /// Referenced a young object when last traced.
    has_young: bool = false,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [untracked](#const-gcheader-untracked) |  |  |  |

<a id="const-gcheader-untracked"></a>

### GcHeader.untracked

```zig
pub const untracked = std.math.maxInt(u32);
```

<a id="type-gcobject"></a>

## GcObject

Queue entries own identities, never pointers into growable registries.

```zig
pub const GcObject = union(enum) {
    table: *Table,
    userdata: *Userdata,
    closure: *Closure,
    upvalue: *Upvalue,
    thread: *Thread,
};
```

<a id="type-gcphase"></a>

## GcPhase

```zig
pub const GcPhase = enum {
    pause,
    propagate,
    atomic,
    sweep_threads,
    sweep_closures,
    sweep_upvalues,
    sweep_strings,
    sweep_userdata,
    sweep_tables,
    finalize,
};
```

<a id="type-gccycle"></a>

## GcCycle

```zig
pub const GcCycle = enum {
    major,
    minor,
};
```

<a id="type-gcgenerations"></a>

## GcGenerations

```zig
pub const GcGenerations = struct {
    string_allocations: usize = 0,
    table_allocations: usize = 0,
    userdata_allocations: usize = 0,
    closure_allocations: usize = 0,
    upvalue_allocations: usize = 0,
    thread_allocations: usize = 0,
};
```

<a id="type-gcmode"></a>

## GcMode

```zig
pub const GcMode = enum {
    incremental,
    generational,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [name](#fn-gcmode-name) | `self: GcMode` | `[]const u8` |  |

<a id="fn-gcmode-name"></a>

### GcMode.name

```zig
pub fn name(self: GcMode) []const u8
```

References: [`GcMode`](#type-gcmode)

<a id="type-gcparam"></a>

## GcParam

```zig
pub const GcParam = enum {
    minormul,
    majorminor,
    minormajor,
    pause,
    stepmul,
    stepsize,
};
```

<a id="type-gcparams"></a>

## GcParams

Collection tuning. Values are percentages except `stepsize`, in bytes. The Zig API accepts
0 through maxInt(i32) without the rounding `collectgarbage("param", ...)` applies.

```zig
pub const GcParams = struct {
    /// Heap growth before the next minor collection.
    minormul: i64 = 20,
    /// Percentage of heap growth a major collection must reclaim to return to minor collections.
    majorminor: i64 = 50,
    /// Heap growth since the last major collection before another is requested; zero disables the transition.
    minormajor: i64 = 70,
    /// Heap size relative to the last collection before starting another full cycle.
    pause: i64 = 250,
    /// Work multiplier for each step.
    stepmul: i64 = 200,
    /// Allocation between steps, in bytes; also used to determine step work.
    stepsize: i64 = 200,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [get](#fn-gcparams-get) | `self: GcParams, param: GcParam` | `i64` |  |
| [set](#fn-gcparams-set) | `self: *GcParams, param: GcParam, value: i64` | `void` |  |

<a id="fn-gcparams-get"></a>

### GcParams.get

```zig
pub fn get(self: GcParams, param: GcParam) i64
```

References: [`GcParams`](#type-gcparams), [`GcParam`](#type-gcparam)

<a id="fn-gcparams-set"></a>

### GcParams.set

```zig
pub fn set(self: *GcParams, param: GcParam, value: i64) void
```

References: [`GcParams`](#type-gcparams), [`GcParam`](#type-gcparam)

<a id="type-weakmode"></a>

## WeakMode

```zig
pub const WeakMode = struct {
    keys: bool = false,
    values: bool = false,
};
```

<a id="type-runtimeallocationstats"></a>

## RuntimeAllocationStats

```zig
pub const RuntimeAllocationStats = struct {
    strings: usize,
    tables: usize,
    closures: usize,
    upvalues: usize,
    threads: usize,
    bytes: usize,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [total](#fn-runtimeallocationstats-total) | `self: RuntimeAllocationStats` | `usize` |  |

<a id="fn-runtimeallocationstats-total"></a>

### RuntimeAllocationStats.total

```zig
pub fn total(self: RuntimeAllocationStats) usize
```

References: [`RuntimeAllocationStats`](#type-runtimeallocationstats)

