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
- [compile.compiler](../compile/compiler.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
- [runtime](../runtime.md)
- [runtime.chunk](../runtime/chunk.md)
- [runtime.types](../runtime/types.md)
- [runtime.value](../runtime/value.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.state](../runtime/state.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.host](../runtime/host.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [stdlib.table](../stdlib/table.md)
- [stdlib.string](../stdlib/string.md)
- [stdlib.math](../stdlib/math.md)
- [stdlib.utf8](../stdlib/utf8.md)
- [stdlib.coroutine](../stdlib/coroutine.md)
- [stdlib.debug](../stdlib/debug.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.io](../stdlib/io.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
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

## Types

- [RuntimeError](#type-runtimeerror)
- [Value](#type-value)
- [NativeFn](#type-nativefn)
- [AllocatorLifetime](#type-allocatorlifetime)
- [UserdataPayload](#type-userdatapayload)
- [ProtectedCallResult](#type-protectedcallresult)
- [CallbackReturns](#type-callbackreturns)
- [ApiCallbackContext](#type-apicallbackcontext)
- [RuntimeErrorPayload](#type-runtimeerrorpayload)
- [ProtectedCallContext](#type-protectedcallcontext)
- [ProtectedContinuationKind](#type-protectedcontinuationkind)
- [ProtectedContinuation](#type-protectedcontinuation)
- [GenericForContinuation](#type-genericforcontinuation)
- [PairsContinuation](#type-pairscontinuation)
- [BranchContinuation](#type-branchcontinuation)
- [TailCallContinuation](#type-tailcallcontinuation)
- [CallOneContinuationResult](#type-callonecontinuationresult)
- [CallOneContinuation](#type-callonecontinuation)
- [CoroutineResumeResult](#type-coroutineresumeresult)
- [Closure](#type-closure)
- [Upvalue](#type-upvalue)
- [TableEntry](#type-tableentry)
- [Table](#type-table)
- [UserdataScope](#type-userdatascope)
- [Userdata](#type-userdata)
- [Thread](#type-thread)
- [ThreadStatus](#type-threadstatus)
- [CallFrame](#type-callframe)
- [StringAllocation](#type-stringallocation)
- [GcMeta](#type-gcmeta)
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
- [TableEntryIndex](#const-tableentryindex)
- [PointerAllocationIndex](#const-pointerallocationindex)

<a id="type-runtimeerror"></a>

## RuntimeError

```zig
pub const RuntimeError = error{
    RuntimeError,
    StackOverflow,
    UnsupportedOpcode,
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
    string: []const u8,
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

<a id="type-nativefn"></a>

## NativeFn

```zig
pub const NativeFn = enum {
    load,
    type,
    tonumber,
    warn,
    table_concat,
    table_dedup,
    table_insert,
    table_move,
    table_pack,
    table_remove,
    table_sort,
    table_unpack,
    string_byte,
    string_char,
    string_dump,
    string_find,
    string_format,
    string_gmatch,
    string_gmatch_iter,
    string_gsub,
    string_len,
    string_lower,
    string_match,
    string_pack,
    string_packsize,
    string_rep,
    string_reverse,
    string_rsplit,
    string_split,
    string_strip,
    string_sub,
    string_unpack,
    string_upper,
    math_abs,
    math_acos,
    math_asin,
    math_atan,
    math_ceil,
    math_cos,
    math_deg,
    math_exp,
    math_floor,
    math_fmod,
    math_frexp,
    math_ldexp,
    math_log,
    math_max,
    math_min,
    math_modf,
    math_rad,
    math_random,
    math_randomseed,
    math_sin,
    math_sqrt,
    math_tan,
    math_tointeger,
    math_type,
    math_ult,
    utf8_char,
    utf8_codepoint,
    utf8_codes,
    utf8_codes_iter,
    utf8_len,
    utf8_offset,
    loadfile,
    dofile,
    require,
    package_searchpath,
    package_searcher_preload,
    package_searcher_lua,
    io_read,
    io_write,
    io_open,
    io_input,
    io_output,
    io_close,
    io_flush,
    io_lines,
    io_tmpfile,
    io_type,
    io_file_read,
    io_file_write,
    io_file_close,
    io_file_seek,
    io_file_flush,
    io_file_lines,
    io_file_setvbuf,
    io_lines_iter,
    os_time,
    os_clock,
    os_date,
    os_getenv,
    os_setlocale,
    os_execute,
    os_remove,
    os_rename,
    os_tmpname,
    os_difftime,
    debug_getinfo,
    debug_getupvalue,
    debug_setupvalue,
    debug_upvalueid,
    debug_upvaluejoin,
    debug_getlocal,
    debug_setlocal,
    debug_getregistry,
    debug_sethook,
    debug_gethook,
    debug_setmetatable,
    debug_setuservalue,
    debug_getuservalue,
    json_read,
    json_write,
    toml_read,
    toml_write,
    msgpack_read,
    msgpack_write,
    csv_read,
    csv_write,
    fs_read,
    fs_write,
    fs_open,
    fs_stat,
    fs_exists,
    fs_list,
    fs_scandir,
    fs_walk,
    fs_mkdir,
    fs_remove,
    fs_copy,
    fs_rename,
    fs_move,
    fs_touch,
    fs_open_dir,
    fs_iterator_next,
    fs_iterator_close,
    fs_iterator_skip,
    fs_error_tostring,
    fs_file_stat,
    fs_file_tell,
    fs_file_truncate,
    fs_file_path,
    fs_dir_entries,
    fs_dir_walk,
    fs_dir_open,
    fs_dir_stat,
    fs_dir_mkdir,
    fs_dir_remove,
    fs_dir_close,
    fs_path_join,
    fs_path_normalize,
    fs_path_basename,
    fs_path_dirname,
    fs_path_extension,
    fs_path_stem,
    fs_path_is_absolute,
    fs_path_relative,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [name](#fn-nativefn-name) | `self: NativeFn` | `[]const u8` |  |

<a id="fn-nativefn-name"></a>

### NativeFn.name

```zig
pub fn name(self: NativeFn) []const u8
```

References: [`NativeFn`](#type-nativefn)

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

Keeps allocator infrastructure alive while shared userdata outlives its VM.
Shared allocator infrastructure can outlive its State and be destroyed by
any retaining thread. Retain requires an existing owned reference; acq_rel
release publishes prior accesses and acquires them before final destruction.

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
    /// Known inline storage owned by this payload; external/nested storage is
    /// accounted by the host allocator, not inferred through opaque pointers.
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

Stores small callback results inline. GC visits each callback’s results through items().
Contains no self pointers.

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
    diagnostic: []const u8,
    argument: errors.ArgumentError,
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
    relative_base: bytecode.Register,
    absolute_base: usize,
    stack_len: usize,
    last_result_base: usize,
    last_result_count: usize,
    last_error: ?RuntimeErrorPayload,
};
```

<a id="type-protectedcontinuationkind"></a>

## ProtectedContinuationKind

```zig
pub const ProtectedContinuationKind = enum {
    pcall,
    xpcall,
    xpcall_handler,
};
```

<a id="type-protectedcontinuation"></a>

## ProtectedContinuation

```zig
pub const ProtectedContinuation = struct {
    order: usize,
    context: ProtectedCallContext,
    base: bytecode.Register,
    return_count: u16,
    kind: ProtectedContinuationKind,
    handler: Value = .nil,
    handler_depth: usize = 0,
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
    base: bytecode.Register,
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
    base: bytecode.Register,
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
    discard,
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

<a id="type-closure"></a>

## Closure

```zig
pub const Closure = struct {
    rollback: ?*@import("rollback.zig").Record(Closure) = null,
    proto: *const proto_mod.Proto,
    upvalues: []*Upvalue,
    constants: ?[]?Value = null,
    stripped_debug: bool = false,
    marked: bool = false,
    gc: GcMeta = .{},
};
```

<a id="type-upvalue"></a>

## Upvalue

```zig
pub const Upvalue = struct {
    rollback: ?*@import("rollback.zig").Record(Upvalue) = null,
    owner: *Thread,
    stack_index: usize,
    closed: Value = .nil,
    is_open: bool = true,
    next: ?*Upvalue = null,
    marked: bool = false,
    gc: GcMeta = .{},
};
```

<a id="type-tableentry"></a>

## TableEntry

```zig
pub const TableEntry = struct {
    key: Value,
    value: Value,
};
```

<a id="const-tableentryindex"></a>

## TableEntryIndex

```zig
pub const TableEntryIndex = std.HashMap(Value, usize, ValueHashContext, std.hash_map.default_max_load_percentage);
```

References: [`Value`](#type-value)

<a id="type-table"></a>

## Table

```zig
pub const Table = struct {
    rollback: ?*@import("rollback.zig").Record(Table) = null,
    array: std.ArrayList(Value) = .empty,
    entries: std.ArrayList(TableEntry) = .empty,
    entry_index: TableEntryIndex,
    metatable: ?*Table = null,
    metatable_prev: ?*Table = null,
    metatable_next: ?*Table = null,
    counts_for_gc_count: bool = true,
    marked: bool = false,
    gc: GcMeta = .{},
    finalizer_registered: bool = false,
    finalizer_next: ?*Table = null,
    finalizer_prev: ?*Table = null,
    finalizer_order: u64 = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [init](#fn-table-init) | `allocator: std.mem.Allocator, array_hint: u32, hash_hint: u32` | `!Table` |  |
| [deinit](#fn-table-deinit) | `self: *Table, allocator: std.mem.Allocator` | `void` |  |
| [get](#fn-table-get) | `self: *const Table, key: Value` | `Value` |  |
| [findEntry](#fn-table-findentry) | `self: *const Table, key: Value` | `?usize` |  |
| [rebuildEntryIndex](#fn-table-rebuildentryindex) | `self: *Table` | `!void` |  |
| [insertHashEntryNoAlloc](#fn-table-inserthashentrynoalloc) | `self: *Table, key: Value, value: Value` | `bool` | Insert an absent hash key using reserved storage. The caller must check that the key is absent; false means growth or snapshot detachment is needed. |
| [set](#fn-table-set) | `self: *Table, allocator: std.mem.Allocator, key: Value, value: Value` | `!void` |  |
| [setExistingNonNil](#fn-table-setexistingnonnil) | `self: *Table, key: Value, value: Value` | `bool` |  |
| [len](#fn-table-len) | `self: *const Table` | `i64` |  |
| [next](#fn-table-next) | `self: *const Table, key: Value` | `![2]Value` |  |
| [removeHashKey](#fn-table-removehashkey) | `self: *Table, key: Value` | `void` |  |
| [removeEntryAt](#fn-table-removeentryat) | `self: *Table, index: usize` | `void` |  |

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

<a id="fn-table-get"></a>

### Table.get

```zig
pub fn get(self: *const Table, key: Value) Value
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-findentry"></a>

### Table.findEntry

```zig
pub fn findEntry(self: *const Table, key: Value) ?usize
```

References: [`Table`](#type-table), [`Value`](#type-value)

<a id="fn-table-rebuildentryindex"></a>

### Table.rebuildEntryIndex

```zig
pub fn rebuildEntryIndex(self: *Table) !void
```

References: [`Table`](#type-table)

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
pub fn len(self: *const Table) i64
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

<a id="type-userdata"></a>

## Userdata

```zig
pub const Userdata = struct {
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
    marked: bool = false,
    gc: GcMeta = .{},
    finalized: bool = false,
    finalization_pending: bool = false,
    finalizer_next: ?*Userdata = null,
};
```

<a id="type-thread"></a>

## Thread

```zig
pub const Thread = struct {
    rollback: ?*@import("rollback.zig").Record(Thread) = null,
    /// A Lua value has exposed this thread beyond its current host call.
    exposed: bool = false,
    stack: std.ArrayList(Value) = .empty,
    frames: std.ArrayList(CallFrame) = .empty,
    yield_values: std.ArrayList(Value) = .empty,
    protected_continuations: std.ArrayList(ProtectedContinuation) = .empty,
    generic_for_continuations: std.ArrayList(GenericForContinuation) = .empty,
    pairs_continuations: std.ArrayList(PairsContinuation) = .empty,
    continuation_order: usize = 0,
    tail_call_continuations: std.ArrayList(TailCallContinuation) = .empty,
    call_one_continuations: std.ArrayList(CallOneContinuation) = .empty,
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
    traceback_native_name: ?[]const u8 = null,
    protected_close_depth: usize = 0,
    close_error_value: ?Value = null,
    error_traceback: ?[]const u8 = null,
    pending_unwind_error: ?Value = null,
    pending_unwind_resume_frame_count: usize = 0,
    pending_unwind_target_frame_count: usize = 0,
    resume_parent: ?*Thread = null,
    entry: Value = .nil,
    marked: bool = false,
    gc: GcMeta = .{},
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
| [ensureStack](#fn-thread-ensurestack) | `self: *Thread, allocator: std.mem.Allocator, size: usize, limit: usize` | `!void` |  |

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

<a id="fn-thread-ensurestack"></a>

### Thread.ensureStack

```zig
pub fn ensureStack(self: *Thread, allocator: std.mem.Allocator, size: usize, limit: usize) !void
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

<a id="type-callframe"></a>

## CallFrame

```zig
pub const CallFrame = struct {
    closure: *Closure,
    proto: *const proto_mod.Proto,
    base: usize,
    pc: usize,
    return_start: usize,
    return_count: u16,
    varargs: []const Value,
    owns_varargs: bool = false,
    vararg_table_local: Value = .nil,
    last_hook_line: ?usize = null,
    debug_name_override: ?[]const u8 = null,
    debug_namewhat_override: ?[]const u8 = null,
    is_tail_call: bool = false,
    pending_returns: ?[]Value = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-callframe-deinit) | `self: *CallFrame, allocator: std.mem.Allocator` | `void` |  |

<a id="fn-callframe-deinit"></a>

### CallFrame.deinit

```zig
pub fn deinit(self: *CallFrame, allocator: std.mem.Allocator) void
```

References: [`CallFrame`](#type-callframe)

<a id="type-stringallocation"></a>

## StringAllocation

```zig
pub const StringAllocation = struct {
    bytes: []const u8,
    marked: bool = false,
    gc: GcMeta = .{},
};
```

<a id="const-pointerallocationindex"></a>

## PointerAllocationIndex

```zig
pub const PointerAllocationIndex = std.AutoHashMap(usize, usize);
```

<a id="type-gcmeta"></a>

## GcMeta

Collector scratch state never participates in logical rollback dirtiness.

```zig
pub const GcMeta = struct {
    epoch: u64 = 0,
    generation: u64 = 0,
    color: enum { white, gray, black } = .white,
    age: enum { new, survivor, old } = .new,
    remembered: bool = false,
    weak_epoch: u64 = 0,
    tables_epoch: u64 = 0,
    has_young: bool = false,
    storage_bytes: usize = 0,
};
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

Collection tuning. Values are percentages except `stepsize`, which is in bytes.
The Zig API accepts values from 0 through maxInt(i32) without rounding.
Lua's `collectgarbage("param", ...)` rounds values to Lua's parameter format.

```zig
pub const GcParams = struct {
    /// Heap growth before the next minor collection.
    minormul: i64 = 20,
    /// Fraction of the heap a major collection must reclaim to return to minor collections.
    majorminor: i64 = 50,
    /// Heap growth since the last major collection before another is requested.
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

