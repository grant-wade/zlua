# runtime.state

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
- [runtime.budget](../runtime/budget.md)
- [runtime.strings](../runtime/strings.md)
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

## Types

- [StartupPhase](#type-startupphase)
- [OutputFlush](#type-outputflush)
- [StateOptions](#type-stateoptions)
- [HostErrorHandler](#type-hosterrorhandler)
- [State](#type-state)

## Constants

- [lua_max_c_calls](#const-lua_max_c_calls)
- [stack_error_frames](#const-stack_error_frames)
- [stack_error_values](#const-stack_error_values)
- [max_metamethod_depth](#const-max_metamethod_depth)

## Aliases

- [RuntimeError](#alias-runtimeerror)
- [Value](#alias-value)
- [NativeFn](#alias-nativefn)
- [UserdataFinalizer](#alias-userdatafinalizer)
- [UserdataDeinit](#alias-userdatadeinit)
- [ProtectedCallResult](#alias-protectedcallresult)
- [ApiCallbackDispatchFn](#alias-apicallbackdispatchfn)
- [ApiCallbackContext](#alias-apicallbackcontext)
- [RuntimeErrorPayload](#alias-runtimeerrorpayload)
- [StdlibMode](#alias-stdlibmode)
- [MemoryFile](#alias-memoryfile)
- [MemoryFilesystem](#alias-memoryfilesystem)
- [FilesystemCapability](#alias-filesystemcapability)
- [HostDirectory](#alias-hostdirectory)
- [FilesystemFileKind](#alias-filesystemfilekind)
- [FilesystemFileStat](#alias-filesystemfilestat)
- [FilesystemDirectoryEntry](#alias-filesystemdirectoryentry)
- [EnvironmentCapability](#alias-environmentcapability)
- [ClockCapability](#alias-clockcapability)
- [ProcessCapability](#alias-processcapability)
- [ProcessResult](#alias-processresult)
- [Closure](#alias-closure)
- [Upvalue](#alias-upvalue)
- [Table](#alias-table)
- [Userdata](#alias-userdata)
- [Thread](#alias-thread)
- [GcMode](#alias-gcmode)
- [GcParam](#alias-gcparam)

<a id="alias-runtimeerror"></a>

## RuntimeError

```zig
pub const RuntimeError = types.RuntimeError;
```

<a id="const-lua_max_c_calls"></a>

## lua_max_c_calls

```zig
pub const lua_max_c_calls: usize = 200;
```

<a id="const-stack_error_frames"></a>

## stack_error_frames

```zig
pub const stack_error_frames: usize = 32;
```

<a id="const-stack_error_values"></a>

## stack_error_values

```zig
pub const stack_error_values: usize = 200;
```

<a id="const-max_metamethod_depth"></a>

## max_metamethod_depth

```zig
pub const max_metamethod_depth: usize = 15;
```

<a id="alias-value"></a>

## Value

```zig
pub const Value = types.Value;
```

<a id="alias-nativefn"></a>

## NativeFn

```zig
pub const NativeFn = types.NativeFn;
```

<a id="alias-userdatafinalizer"></a>

## UserdataFinalizer

```zig
pub const UserdataFinalizer = types.UserdataFinalizer;
```

<a id="alias-userdatadeinit"></a>

## UserdataDeinit

```zig
pub const UserdataDeinit = types.UserdataDeinit;
```

<a id="alias-protectedcallresult"></a>

## ProtectedCallResult

```zig
pub const ProtectedCallResult = types.ProtectedCallResult;
```

<a id="alias-apicallbackdispatchfn"></a>

## ApiCallbackDispatchFn

```zig
pub const ApiCallbackDispatchFn = types.ApiCallbackDispatchFn;
```

<a id="alias-apicallbackcontext"></a>

## ApiCallbackContext

```zig
pub const ApiCallbackContext = types.ApiCallbackContext;
```

<a id="alias-runtimeerrorpayload"></a>

## RuntimeErrorPayload

```zig
pub const RuntimeErrorPayload = types.RuntimeErrorPayload;
```

<a id="alias-stdlibmode"></a>

## StdlibMode

```zig
pub const StdlibMode = stdlib.LibrarySelection;
```

References: [`stdlib.LibrarySelection`](../stdlib.md#type-libraryselection)

<a id="alias-memoryfile"></a>

## MemoryFile

```zig
pub const MemoryFile = host.MemoryFile;
```

<a id="alias-memoryfilesystem"></a>

## MemoryFilesystem

```zig
pub const MemoryFilesystem = host.MemoryFilesystem;
```

<a id="alias-filesystemcapability"></a>

## FilesystemCapability

```zig
pub const FilesystemCapability = host.FilesystemCapability;
```

<a id="alias-hostdirectory"></a>

## HostDirectory

```zig
pub const HostDirectory = host.HostDirectory;
```

<a id="alias-filesystemfilekind"></a>

## FilesystemFileKind

```zig
pub const FilesystemFileKind = host.FileKind;
```

<a id="alias-filesystemfilestat"></a>

## FilesystemFileStat

```zig
pub const FilesystemFileStat = host.FileStat;
```

<a id="alias-filesystemdirectoryentry"></a>

## FilesystemDirectoryEntry

```zig
pub const FilesystemDirectoryEntry = host.DirectoryEntry;
```

<a id="alias-environmentcapability"></a>

## EnvironmentCapability

```zig
pub const EnvironmentCapability = host.EnvironmentCapability;
```

<a id="alias-clockcapability"></a>

## ClockCapability

```zig
pub const ClockCapability = host.ClockCapability;
```

<a id="alias-processcapability"></a>

## ProcessCapability

```zig
pub const ProcessCapability = host.ProcessCapability;
```

<a id="alias-processresult"></a>

## ProcessResult

```zig
pub const ProcessResult = host.ProcessResult;
```

<a id="alias-closure"></a>

## Closure

```zig
pub const Closure = types.Closure;
```

<a id="alias-upvalue"></a>

## Upvalue

```zig
pub const Upvalue = types.Upvalue;
```

<a id="alias-table"></a>

## Table

```zig
pub const Table = types.Table;
```

<a id="alias-userdata"></a>

## Userdata

```zig
pub const Userdata = types.Userdata;
```

<a id="alias-thread"></a>

## Thread

```zig
pub const Thread = types.Thread;
```

<a id="alias-gcmode"></a>

## GcMode

```zig
pub const GcMode = types.GcMode;
```

<a id="alias-gcparam"></a>

## GcParam

```zig
pub const GcParam = types.GcParam;
```

<a id="type-startupphase"></a>

## StartupPhase

```zig
pub const StartupPhase = enum {
    state,
    globals,
    libraries,
    gc_baseline,
};
```

<a id="type-outputflush"></a>

## OutputFlush

When stdout/stderr writers flush, beyond `io.flush`, `file:flush`, `os.exit`,
and before `os.execute`/`io.popen` start a child process.

```zig
pub const OutputFlush = enum {
    /// Only at the points above.
    explicit,
    /// After each `print`, like C Lua's `lua_writeline`.
    print,
    /// After each write containing a newline, like a line-buffered C stream.
    line,
    /// After every write, like an unbuffered C stream.
    always,
};
```

<a id="type-stateoptions"></a>

## StateOptions

```zig
pub const StateOptions = struct {
    stdlib: StdlibMode = .full,
    io: ?std.Io = null,
    stdout: ?*std.Io.Writer = null,
    stderr: ?*std.Io.Writer = null,
    stdout_flush: OutputFlush = .explicit,
    stderr_flush: OutputFlush = .explicit,
    /// Also keep Lua stdout/stderr bytes in `State.stdout`/`State.stderr`.
    capture_output: bool = true,
    /// Start with Lua warnings on.
    warnings: bool = false,
    /// Receives warnings instead of stderr.
    warning_handler: ?host.WarningHandler = null,
    filesystem: FilesystemCapability = .disabled,
    environment: EnvironmentCapability = .disabled,
    clock: ClockCapability = .system,
    process: ProcessCapability = .disabled,
    stdin: []const u8 = "",
    /// Borrowed stdin stream that takes precedence over `stdin`. Reads are not
    /// undone by snapshot reset.
    stdin_reader: ?*std.Io.Reader = null,
    /// Largest file the libraries read at once.
    max_file_bytes: usize = host.default_max_file_bytes,
    /// Recorded for the embedding API; direct runtime users enforce it through their allocator.
    max_memory: ?usize = null,
    max_stack_values: ?usize = null,
    max_call_frames: ?usize = null,
    max_instructions: ?u64 = null,
    debug_errors: bool = false,
    trace_vm: bool = false,
};
```

<a id="type-hosterrorhandler"></a>

## HostErrorHandler

Handles a runtime error escaping a host entry point. Runs at the error point,
before the failing frames unwind or `__close` runs.

```zig
pub const HostErrorHandler = struct {
    /// Lua message handler with `xpcall` semantics.
    message_handler: Value = .nil,
    /// Receives a traceback the caller frees with the state allocator.
    traceback: ?*?[]u8 = null,
    /// End the traceback with `[C]: in ?`, as `lua.c` does.
    host_frame: bool = false,
};
```

<a id="type-state"></a>

## State

```zig
pub const State = struct {
    rollback: ?*rollback_mod.Journal = null,
    userdata_scope: ?*types.UserdataScope = null,
    value_roots: ?*types.ValueRoots = null,
    /// Includes direct interpreter entry, nested calls, and suspended host callbacks.
    execution_depth: usize = 0,
    allocator_lifetime: ?*types.AllocatorLifetime = null,
    snapshot_busy: bool = false,
    discarding: bool = false,
    allocator: std.mem.Allocator,
    global_table: ?*Table = null,
    strings: strings_mod.Strings,
    string_allocations: std.ArrayList(StringAllocation) = .empty,
    string_allocation_index: PointerAllocationIndex,
    table_allocations: std.ArrayList(*Table) = .empty,
    table_allocation_index: PointerAllocationIndex,
    object_allocation_index: std.AutoHashMapUnmanaged(usize, usize) = .empty,
    table_metatable_head: ?*Table = null,
    table_finalizer_head: ?*Table = null,
    table_finalizer_serial: u64 = 0,
    table_pending_finalizer_head: ?*Table = null,
    /// Userdata awaiting Lua `__gc`, ordered together with `table_pending_finalizer_head`.
    userdata_lua_pending_head: ?*Userdata = null,
    userdata_pending_finalizer_head: ?*Userdata = null,
    table_metatable_count: usize = 0,
    userdata_allocations: std.ArrayList(*Userdata) = .empty,
    closure_allocations: std.ArrayList(*Closure) = .empty,
    upvalue_allocations: std.ArrayList(*Upvalue) = .empty,
    thread_allocations: std.ArrayList(*Thread) = .empty,
    proto_allocations: std.ArrayList(*proto_mod.Proto) = .empty,
    /// Prefix owned by the API state's retained immutable snapshot.
    borrowed_proto_count: usize = 0,
    source_allocations: std.ArrayList([]const u8) = .empty,
    api_roots: std.ArrayList(Value) = .empty,
    stdout: std.ArrayList(u8) = .empty,
    stderr: std.ArrayList(u8) = .empty,
    options: StateOptions,
    stdin_pos: usize = 0,
    /// Set by `os.exit` while the state unwinds with `error.LuaExit`.
    exit_request: ?host.ExitRequest = null,
    local_zone: ?*timezone.Zone = null,
    /// Advanced by filesystem mutations so buffered file handles reload contents.
    file_generation: u64 = 0,
    last_error: ?RuntimeErrorPayload = null,
    warnings_on: bool = false,
    /// The current error already went through a message handler or must skip one.
    error_handled: bool = false,
    current_thread: ?*Thread = null,
    api_callback_dispatch: ?ApiCallbackDispatchFn = null,
    api_callback_user_data: ?*anyopaque = null,
    active_api_callback: ?*ApiCallbackContext = null,
    coroutine_close_depth: usize = 0,
    string_metatable: ?*Table = null,
    number_metatable: ?*Table = null,
    boolean_metatable: ?*Table = null,
    nil_metatable: ?*Table = null,
    file_metatable: ?*Table = null,
    fs_file_metatable: ?*Table = null,
    /// Rooted outside Lua-visible tables.
    io_input: ?*Userdata = null,
    io_output: ?*Userdata = null,
    library_tables: std.EnumArray(stdlib.LibraryTable, ?*Table) = .initFill(null),
    gc: gc_mod.Gc = .{},
    random_state: [4]u64 = .{ 0x123456789abcdef0, 0xff, 0xfedcba9876543210, 0 },
    budget: budget_mod.Budget = .{},
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [max_c_calls](#alias-state-max_c_calls) |  |  |  |
| [registerAllocation](#fn-state-registerallocation) | `self: *State, comptime field: []const u8, item: anytype` | `!void` |  |
| [init](#fn-state-init) | `allocator: std.mem.Allocator` | `!State` |  |
| [initWithOptions](#fn-state-initwithoptions) | `allocator: std.mem.Allocator, options: StateOptions` | `!State` |  |
| [initWithOptionsObserved](#fn-state-initwithoptionsobserved) | `allocator: std.mem.Allocator,         options: StateOptions,         observer_context: anytype,         comptime observe: anytype,` | `!State` |  |
| [stackValueLimit](#fn-state-stackvaluelimit) | `self: *const State` | `usize` |  |
| [stressPending](#fn-state-stresspending) | `self: *const State` | `bool` |  |
| [callFrameLimit](#fn-state-callframelimit) | `self: *const State` | `usize` |  |
| [fileMetatable](#fn-state-filemetatable) | `state: *State` | `!*Table` |  |
| [fsFileMetatable](#fn-state-fsfilemetatable) | `state: *State` | `!*Table` | Extends the &#96;FILE*&#96; metatable with &#96;stat&#96;, &#96;tell&#96;, &#96;truncate&#96;, &#96;path&#96;, and &#96;sync&#96;. |
| [isBuiltinUserdata](#fn-state-isbuiltinuserdata) | `userdata: *const Userdata` | `bool` |  |
| [finalizeBuiltinUserdata](#fn-state-finalizebuiltinuserdata) | `self: *State, userdata: *Userdata` | `bool` | Returns false for userdata not implemented by the runtime. |
| [closeFinalizerOrder](#fn-state-closefinalizerorder) | `userdata: *Userdata` | `?u64` |  |
| [builtinFinalizerOrder](#fn-state-builtinfinalizerorder) | `userdata: *Userdata` | `u64` |  |
| [discard](#fn-state-discard) | `self: *State` | `void` |  |
| [deinit](#fn-state-deinit) | `self: *State` | `void` | Like &#96;lua_close&#96;: runs pending finalizers newest first, restarting the instruction budget for each, then frees the state. |
| [deinitWithoutFinalizers](#fn-state-deinitwithoutfinalizers) | `self: *State` | `void` | Skips Lua &#96;__gc&#96; metamethods, like exiting without &#96;lua_close&#96;; open files are still closed. |
| [setTableRaw](#fn-state-settableraw) | `self: *State, table: *Table, key: Value, value: Value` | `!void` |  |
| [declareGlobal](#fn-state-declareglobal) | `self: *State, thread: *Thread, name: []const u8, table_register: bytecode.Register, value_register: bytecode.Register` | `!void` |  |
| [setGlobal](#fn-state-setglobal) | `self: *State, name: []const u8, value: Value` | `!void` |  |
| [getGlobalValue](#fn-state-getglobalvalue) | `self: *State, name: []const u8` | `Value` |  |
| [getGlobal](#fn-state-getglobal) | `self: *State, name: []const u8` | `Value` |  |
| [putGlobal](#fn-state-putglobal) | `self: *State, name: []const u8, value: Value` | `!void` |  |
| [rootValue](#fn-state-rootvalue) | `self: *State, value: Value` | `!usize` |  |
| [unrootValue](#fn-state-unrootvalue) | `self: *State, index: usize` | `void` |  |
| [pushValueRoots](#fn-state-pushvalueroots) | `self: *State, roots: *types.ValueRoots, values: []const Value` | `void` |  |
| [popValueRoots](#fn-state-popvalueroots) | `self: *State, roots: *types.ValueRoots` | `void` |  |
| [rootedValue](#fn-state-rootedvalue) | `self: *const State, index: usize` | `Value` |  |
| [activeRootCount](#fn-state-activerootcount) | `self: State` | `usize` |  |
| [setApiCallbackDispatch](#fn-state-setapicallbackdispatch) | `self: *State, dispatch: ApiCallbackDispatchFn, user_data: *anyopaque` | `void` |  |
| [callApiCallbackDispatch](#fn-state-callapicallbackdispatch) | `self: *State, thread: *Thread, op: bytecode.Call, callback_id: usize` | `!void` |  |
| [newTableWithHints](#fn-state-newtablewithhints) | `self: *State, array_hint: u32, hash_hint: u32` | `!Value` |  |
| [newUserdata](#fn-state-newuserdata) | `self: *State, ptr: *anyopaque, type_id: usize, type_name: []const u8, finalizer: ?UserdataFinalizer, finalizer_data: ?*const anyopaque, deinit_fn: ?UserdataDeinit` | `!Value` |  |
| [newClosure](#fn-state-newclosure) | `self: *State, thread: *Thread, proto: *const proto_mod.Proto` | `!Value` |  |
| [returnValues](#fn-state-returnvalues) | `self: *State, thread: *Thread, base: u32, return_count: u16, values: []const Value` | `!void` |  |
| [expectTable](#fn-state-expecttable) | `self: *State, value: Value` | `!*Table` |  |
| [expectString](#fn-state-expectstring) | `self: *State, value: Value` | `![]const u8` |  |
| [expectArgumentThread](#fn-state-expectargumentthread) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32` | `!*Thread` | Like &#96;getco&#96; in lcorolib. |
| [fail](#fn-state-fail) | `self: *State, message: []const u8` | `RuntimeError` |  |
| [failArgumentMessage](#fn-state-failargumentmessage) | `self: *State, function_name: []const u8, index: u32, message: []const u8` | `RuntimeError` |  |
| [failArgumentType](#fn-state-failargumenttype) | `self: *State, function_name: []const u8, index: u32, expected: []const u8, actual: Value` | `RuntimeError` |  |
| [failLibrary](#fn-state-faillibrary) | `self: *State, message: []const u8` | `RuntimeError` | Like &#96;luaL_error&#96;: prefixes the calling Lua code's position. |
| [withLibraryWhere](#fn-state-withlibrarywhere) | `self: *State, value: Value` | `!Value` | Prefixes a string error with &#96;luaL_where(L, 1)&#96;, as &#96;coroutine.wrap&#96; does. |
| [failLibraryFmt](#fn-state-faillibraryfmt) | `self: *State, comptime fmt: []const u8, args: anytype` | `RuntimeError` |  |
| [activeNativeCall](#fn-state-activenativecall) | `thread: *Thread` | `?types.NativeCall` |  |
| [appendGlobalFunctionName](#fn-state-appendglobalfunctionname) | `self: *State, out: *std.ArrayList(u8), callee: Value` | `!bool` | Like &#96;pushglobalfuncname&#96;. |
| [expectArgumentString](#fn-state-expectargumentstring) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32` | `![]const u8` | Like &#96;luaL_checklstring&#96;; numbers are converted in place, keeping the string reachable. |
| [optionalArgumentString](#fn-state-optionalargumentstring) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32` | `!?[]const u8` |  |
| [expectArgumentTable](#fn-state-expectargumenttable) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32` | `!*Table` |  |
| [argumentNumber](#fn-state-argumentnumber) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32` | `!f64` |  |
| [optionalArgumentInteger](#fn-state-optionalargumentinteger) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32, default: i64` | `!i64` |  |
| [argumentInteger](#fn-state-argumentinteger) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32` | `!i64` |  |
| [failValue](#fn-state-failvalue) | `self: *State, value: Value` | `RuntimeError` |  |
| [throwValue](#fn-state-throwvalue) | `self: *State, value: Value` | `RuntimeError` |  |
| [rethrowValue](#fn-state-rethrowvalue) | `self: *State, value: Value` | `RuntimeError` | For an error that already went through its message handler. |
| [currentErrorValue](#fn-state-currenterrorvalue) | `self: *State` | `Value` |  |

<a id="alias-state-max_c_calls"></a>

### State.max_c_calls

```zig
pub const max_c_calls = lua_max_c_calls;
```

<a id="fn-state-registerallocation"></a>

### State.registerAllocation

```zig
pub fn registerAllocation(self: *State, comptime field: []const u8, item: anytype) !void
```

References: [`State`](#type-state)

<a id="fn-state-init"></a>

### State.init

```zig
pub fn init(allocator: std.mem.Allocator) !State
```

References: [`State`](#type-state)

<a id="fn-state-initwithoptions"></a>

### State.initWithOptions

```zig
pub fn initWithOptions(allocator: std.mem.Allocator, options: StateOptions) !State
```

References: [`StateOptions`](#type-stateoptions), [`State`](#type-state)

<a id="fn-state-initwithoptionsobserved"></a>

### State.initWithOptionsObserved

```zig
pub fn initWithOptionsObserved(
        allocator: std.mem.Allocator,
        options: StateOptions,
        observer_context: anytype,
        comptime observe: anytype,
    ) !State
```

References: [`StateOptions`](#type-stateoptions), [`State`](#type-state)

<a id="fn-state-stackvaluelimit"></a>

### State.stackValueLimit

```zig
pub fn stackValueLimit(self: *const State) usize
```

References: [`State`](#type-state)

<a id="fn-state-stresspending"></a>

### State.stressPending

```zig
pub fn stressPending(self: *const State) bool
```

References: [`State`](#type-state)

<a id="fn-state-callframelimit"></a>

### State.callFrameLimit

```zig
pub fn callFrameLimit(self: *const State) usize
```

References: [`State`](#type-state)

<a id="fn-state-filemetatable"></a>

### State.fileMetatable

```zig
pub fn fileMetatable(state: *State) !*Table
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-fsfilemetatable"></a>

### State.fsFileMetatable

Extends the `FILE*` metatable with `stat`, `tell`, `truncate`, `path`, and `sync`.

```zig
pub fn fsFileMetatable(state: *State) !*Table
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-isbuiltinuserdata"></a>

### State.isBuiltinUserdata

```zig
pub fn isBuiltinUserdata(userdata: *const Userdata) bool
```

References: [`Userdata`](#alias-userdata)

<a id="fn-state-finalizebuiltinuserdata"></a>

### State.finalizeBuiltinUserdata

Returns false for userdata not implemented by the runtime.

```zig
pub fn finalizeBuiltinUserdata(self: *State, userdata: *Userdata) bool
```

References: [`State`](#type-state), [`Userdata`](#alias-userdata)

<a id="fn-state-closefinalizerorder"></a>

### State.closeFinalizerOrder

```zig
pub fn closeFinalizerOrder(userdata: *Userdata) ?u64
```

References: [`Userdata`](#alias-userdata)

<a id="fn-state-builtinfinalizerorder"></a>

### State.builtinFinalizerOrder

```zig
pub fn builtinFinalizerOrder(userdata: *Userdata) u64
```

References: [`Userdata`](#alias-userdata)

<a id="fn-state-discard"></a>

### State.discard

```zig
pub fn discard(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-deinit"></a>

### State.deinit

Like `lua_close`: runs pending finalizers newest first, restarting the
instruction budget for each, then frees the state.

```zig
pub fn deinit(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-deinitwithoutfinalizers"></a>

### State.deinitWithoutFinalizers

Skips Lua `__gc` metamethods, like exiting without `lua_close`; open files are still closed.

```zig
pub fn deinitWithoutFinalizers(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-settableraw"></a>

### State.setTableRaw

```zig
pub fn setTableRaw(self: *State, table: *Table, key: Value, value: Value) !void
```

References: [`State`](#type-state), [`Table`](#alias-table), [`Value`](#alias-value)

<a id="fn-state-declareglobal"></a>

### State.declareGlobal

```zig
pub fn declareGlobal(self: *State, thread: *Thread, name: []const u8, table_register: bytecode.Register, value_register: bytecode.Register) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-setglobal"></a>

### State.setGlobal

```zig
pub fn setGlobal(self: *State, name: []const u8, value: Value) !void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-getglobalvalue"></a>

### State.getGlobalValue

```zig
pub fn getGlobalValue(self: *State, name: []const u8) Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-getglobal"></a>

### State.getGlobal

```zig
pub fn getGlobal(self: *State, name: []const u8) Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-putglobal"></a>

### State.putGlobal

```zig
pub fn putGlobal(self: *State, name: []const u8, value: Value) !void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-rootvalue"></a>

### State.rootValue

```zig
pub fn rootValue(self: *State, value: Value) !usize
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-unrootvalue"></a>

### State.unrootValue

```zig
pub fn unrootValue(self: *State, index: usize) void
```

References: [`State`](#type-state)

<a id="fn-state-pushvalueroots"></a>

### State.pushValueRoots

```zig
pub fn pushValueRoots(self: *State, roots: *types.ValueRoots, values: []const Value) void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-popvalueroots"></a>

### State.popValueRoots

```zig
pub fn popValueRoots(self: *State, roots: *types.ValueRoots) void
```

References: [`State`](#type-state)

<a id="fn-state-rootedvalue"></a>

### State.rootedValue

```zig
pub fn rootedValue(self: *const State, index: usize) Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-activerootcount"></a>

### State.activeRootCount

```zig
pub fn activeRootCount(self: State) usize
```

References: [`State`](#type-state)

<a id="fn-state-setapicallbackdispatch"></a>

### State.setApiCallbackDispatch

```zig
pub fn setApiCallbackDispatch(self: *State, dispatch: ApiCallbackDispatchFn, user_data: *anyopaque) void
```

References: [`State`](#type-state), [`ApiCallbackDispatchFn`](#alias-apicallbackdispatchfn)

<a id="fn-state-callapicallbackdispatch"></a>

### State.callApiCallbackDispatch

```zig
pub fn callApiCallbackDispatch(self: *State, thread: *Thread, op: bytecode.Call, callback_id: usize) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-newtablewithhints"></a>

### State.newTableWithHints

```zig
pub fn newTableWithHints(self: *State, array_hint: u32, hash_hint: u32) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-newuserdata"></a>

### State.newUserdata

```zig
pub fn newUserdata(self: *State, ptr: *anyopaque, type_id: usize, type_name: []const u8, finalizer: ?UserdataFinalizer, finalizer_data: ?*const anyopaque, deinit_fn: ?UserdataDeinit) !Value
```

References: [`State`](#type-state), [`UserdataFinalizer`](#alias-userdatafinalizer), [`UserdataDeinit`](#alias-userdatadeinit), [`Value`](#alias-value)

<a id="fn-state-newclosure"></a>

### State.newClosure

```zig
pub fn newClosure(self: *State, thread: *Thread, proto: *const proto_mod.Proto) !Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-returnvalues"></a>

### State.returnValues

```zig
pub fn returnValues(self: *State, thread: *Thread, base: u32, return_count: u16, values: []const Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-expecttable"></a>

### State.expectTable

```zig
pub fn expectTable(self: *State, value: Value) !*Table
```

References: [`State`](#type-state), [`Value`](#alias-value), [`Table`](#alias-table)

<a id="fn-state-expectstring"></a>

### State.expectString

```zig
pub fn expectString(self: *State, value: Value) ![]const u8
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-expectargumentthread"></a>

### State.expectArgumentThread

Like `getco` in lcorolib.

```zig
pub fn expectArgumentThread(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !*Thread
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-fail"></a>

### State.fail

```zig
pub fn fail(self: *State, message: []const u8) RuntimeError
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-failargumentmessage"></a>

### State.failArgumentMessage

```zig
pub fn failArgumentMessage(self: *State, function_name: []const u8, index: u32, message: []const u8) RuntimeError
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-failargumenttype"></a>

### State.failArgumentType

```zig
pub fn failArgumentType(self: *State, function_name: []const u8, index: u32, expected: []const u8, actual: Value) RuntimeError
```

References: [`State`](#type-state), [`Value`](#alias-value), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-faillibrary"></a>

### State.failLibrary

Like `luaL_error`: prefixes the calling Lua code's position.

```zig
pub fn failLibrary(self: *State, message: []const u8) RuntimeError
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-withlibrarywhere"></a>

### State.withLibraryWhere

Prefixes a string error with `luaL_where(L, 1)`, as `coroutine.wrap` does.

```zig
pub fn withLibraryWhere(self: *State, value: Value) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-faillibraryfmt"></a>

### State.failLibraryFmt

```zig
pub fn failLibraryFmt(self: *State, comptime fmt: []const u8, args: anytype) RuntimeError
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-activenativecall"></a>

### State.activeNativeCall

```zig
pub fn activeNativeCall(thread: *Thread) ?types.NativeCall
```

References: [`Thread`](#alias-thread)

<a id="fn-state-appendglobalfunctionname"></a>

### State.appendGlobalFunctionName

Like `pushglobalfuncname`.

```zig
pub fn appendGlobalFunctionName(self: *State, out: *std.ArrayList(u8), callee: Value) !bool
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-expectargumentstring"></a>

### State.expectArgumentString

Like `luaL_checklstring`; numbers are converted in place, keeping the string reachable.

```zig
pub fn expectArgumentString(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) ![]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-optionalargumentstring"></a>

### State.optionalArgumentString

```zig
pub fn optionalArgumentString(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !?[]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-expectargumenttable"></a>

### State.expectArgumentTable

```zig
pub fn expectArgumentTable(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !*Table
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Table`](#alias-table)

<a id="fn-state-argumentnumber"></a>

### State.argumentNumber

```zig
pub fn argumentNumber(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !f64
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-optionalargumentinteger"></a>

### State.optionalArgumentInteger

```zig
pub fn optionalArgumentInteger(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32, default: i64) !i64
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-argumentinteger"></a>

### State.argumentInteger

```zig
pub fn argumentInteger(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !i64
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-failvalue"></a>

### State.failValue

```zig
pub fn failValue(self: *State, value: Value) RuntimeError
```

References: [`State`](#type-state), [`Value`](#alias-value), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-throwvalue"></a>

### State.throwValue

```zig
pub fn throwValue(self: *State, value: Value) RuntimeError
```

References: [`State`](#type-state), [`Value`](#alias-value), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-rethrowvalue"></a>

### State.rethrowValue

For an error that already went through its message handler.

```zig
pub fn rethrowValue(self: *State, value: Value) RuntimeError
```

References: [`State`](#type-state), [`Value`](#alias-value), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-currenterrorvalue"></a>

### State.currentErrorValue

```zig
pub fn currentErrorValue(self: *State) Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

