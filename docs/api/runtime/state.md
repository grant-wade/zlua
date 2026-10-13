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

- [luaTypeName](#fn-luatypename)
- [valuesEqual](#fn-valuesequal)
- [truthy](#fn-truthy)
- [toInteger](#fn-tointeger)
- [toNumber](#fn-tonumber)
- [appendLuaString](#fn-appendluastring)
- [localActiveAt](#fn-localactiveat)
- [parseIntegerStrict](#fn-parseintegerstrict)
- [parseLuaNumber](#fn-parseluanumber)
- [floatToInteger](#fn-floattointeger)
- [trimAscii](#fn-trimascii)
- [runtimeArgValue](#fn-runtimeargvalue)
- [argValue](#fn-argvalue)
- [appendErrorValue](#fn-appenderrorvalue)
- [appendValue](#fn-appendvalue)
- [isFileValue](#fn-isfilevalue)
- [isClosedFileValue](#fn-isclosedfilevalue)
- [appendNumber](#fn-appendnumber)
- [appendFmt](#fn-appendfmt)

## Types

- [StartupPhase](#type-startupphase)
- [OutputFlush](#type-outputflush)
- [StateOptions](#type-stateoptions)
- [HostErrorHandler](#type-hosterrorhandler)
- [State](#type-state)
- [CompareOp](#type-compareop)

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

When the runtime flushes a configured stdout or stderr writer. Writers are
always flushed by `io.flush`/`file:flush`, `os.exit`, and before
`os.execute`/`io.popen` start a child process.

```zig
pub const OutputFlush = enum {
    /// Only at the points above; the writer's own buffer decides the rest.
    explicit,
    /// Also after each `print`, like C Lua's `lua_writeline`; other writes
    /// stay buffered like a fully buffered C stream.
    print,
    /// Also after each write containing a newline, like a line-buffered C
    /// stream. This includes every `print`.
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
    /// Streaming hosts with writers can disable this to bound memory.
    capture_output: bool = true,
    /// Start with Lua warnings on. Lua's `warn("@on")` and `warn("@off")` switch them.
    warnings: bool = false,
    /// Receives warnings instead of stderr.
    warning_handler: ?host.WarningHandler = null,
    filesystem: FilesystemCapability = .disabled,
    environment: EnvironmentCapability = .disabled,
    clock: ClockCapability = .system,
    process: ProcessCapability = .disabled,
    stdin: []const u8 = "",
    /// Host stdin stream read incrementally by `io.read`, `io.lines`, and
    /// `loadfile()`. Takes precedence over `stdin` bytes. Borrowed; reads
    /// cannot be undone by snapshot reset.
    stdin_reader: ?*std.Io.Reader = null,
    /// Largest file `io`, `loadfile`, `dofile`, `require`, and `fs` read at once.
    max_file_bytes: usize = host.default_max_file_bytes,
    /// Memory budget retained for embedding API allocator setup and snapshots.
    /// Direct runtime users must enforce this budget through their allocator.
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

Host handling for a runtime error escaping a host entry point. It runs
at the error point, before the failing frames unwind or `__close` runs.

```zig
pub const HostErrorHandler = struct {
    /// Lua message handler with `xpcall` semantics; its first result replaces the error value.
    message_handler: Value = .nil,
    /// Receives a traceback allocated with the state allocator. The caller
    /// initializes it to null and frees any traceback stored there.
    traceback: ?*?[]u8 = null,
    /// End the traceback with `[C]: in ?` for the host entry, as `lua.c` does.
    host_frame: bool = false,
};
```

<a id="type-state"></a>

## State

```zig
pub const State = struct {
    rollback: ?*rollback_mod.Journal = null,
    userdata_scope: ?*types.UserdataScope = null,
    /// Includes direct interpreter entry, nested calls, and suspended host callbacks.
    execution_depth: usize = 0,
    allocator_lifetime: ?*types.AllocatorLifetime = null,
    snapshot_busy: bool = false,
    discarding: bool = false,
    allocator: std.mem.Allocator,
    global_table: ?*Table = null,
    strings: std.StringHashMap([]const u8),
    string_allocations: std.ArrayList(StringAllocation) = .empty,
    string_allocation_index: PointerAllocationIndex,
    table_allocations: std.ArrayList(*Table) = .empty,
    table_allocation_index: PointerAllocationIndex,
    object_allocation_index: std.AutoHashMapUnmanaged(usize, usize) = .empty,
    table_metatable_head: ?*Table = null,
    table_finalizer_head: ?*Table = null,
    table_finalizer_serial: u64 = 0,
    table_pending_finalizer_head: ?*Table = null,
    /// Userdata separated for their Lua `__gc`, in queue order shared with
    /// `table_pending_finalizer_head`.
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
    /// Local time zone loaded on first use by the system clock.
    local_zone: ?*timezone.Zone = null,
    /// Advanced by filesystem mutations so buffered file handles reload contents.
    file_generation: u64 = 0,
    last_error: ?RuntimeErrorPayload = null,
    /// Lua warnings are on, as switched by `@on` and `@off` control messages.
    warnings_on: bool = false,
    /// The current error already went through a message handler (or must
    /// skip one, like a memory error or an error in error handling).
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
    /// Metatable of `fs` file handles, which add the `fs` file methods.
    fs_file_metatable: ?*Table = null,
    /// Default files of `io.read`/`io.write`, rooted outside Lua-visible tables.
    io_input: ?*Userdata = null,
    io_output: ?*Userdata = null,
    zerde_null: ?*Table = null,
    zerde_array_metatable: ?*Table = null,
    zerde_object_metatable: ?*Table = null,
    is_collecting: bool = false,
    collect_after_instruction: bool = false,
    step_after_instruction: bool = false,
    gc_running: bool = true,
    gc_mode: GcMode = .generational,
    gc_params: GcParams = .{},
    gc_next_total: usize = 0,
    gc_known_total: usize = 0,
    gc_epoch: u64 = 1,
    gc_generation: u64 = 1,
    gc_phase: types.GcPhase = .pause,
    gc_cycle: types.GcCycle = .major,
    gc_work: std.ArrayList(types.GcObject) = .empty,
    gc_remembered: std.ArrayList(types.GcObject) = .empty,
    gc_weak: std.ArrayList(*Table) = .empty,
    gc_tables: std.ArrayList(*Table) = .empty,
    gc_finalizers: std.ArrayList(types.FinalizerObject) = .empty,
    gc_major_pending: bool = false,
    gc_cycle_start_total: usize = 0,
    gc_found_young: bool = false,
    gc_old: types.GcGenerations = .{},
    gc_sweep_cursor: usize = 0,
    gc_major_base: usize = 0,
    gc_work_done: usize = 0,
    gc_minor_count: usize = 0,
    mark_all_stack_registers: bool = false,
    conservative_gc_depth: usize = 0,
    random_state: [4]u64 = .{ 0x123456789abcdef0, 0xff, 0xfedcba9876543210, 0 },
    /// Monotonic count of executed VM instructions.
    instruction_count: u64 = 0,
    /// `instruction_count` at the last budget reset; `max_instructions` covers
    /// the instructions executed since then.
    instruction_budget_base: u64 = 0,
    /// Absolute `instruction_count` deadline of the innermost budgeted host
    /// call, already narrowed by enclosing budgeted calls.
    call_instruction_deadline: ?u64 = null,
    /// The dispatch loop enters `vm.executionCheckpoint` once
    /// `instruction_count` reaches this value. Zero forces a recompute.
    instruction_checkpoint: u64 = 0,
    /// Interrupt request shared with host threads; allocated on first use.
    interrupt: ?*vm_mod.InterruptControl = null,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [registerAllocation](#fn-state-registerallocation) | `self: *State, comptime field: []const u8, item: anytype` | `!void` |  |
| [init](#fn-state-init) | `allocator: std.mem.Allocator` | `!State` |  |
| [initWithOptions](#fn-state-initwithoptions) | `allocator: std.mem.Allocator, options: StateOptions` | `!State` |  |
| [initWithOptionsObserved](#fn-state-initwithoptionsobserved) | `allocator: std.mem.Allocator,         options: StateOptions,         observer_context: anytype,         comptime observe: anytype,` | `!State` |  |
| [stackValueLimit](#fn-state-stackvaluelimit) | `self: *const State` | `usize` |  |
| [callFrameLimit](#fn-state-callframelimit) | `self: *const State` | `usize` |  |
| [fileMetatable](#fn-state-filemetatable) | `state: *State` | `!*Table` |  |
| [fsFileMetatable](#fn-state-fsfilemetatable) | `state: *State` | `!*Table` | &#96;fs&#96; file handles share the &#96;FILE*&#96; metamethods, and their method table adds &#96;stat&#96;, &#96;tell&#96;, &#96;truncate&#96;, &#96;path&#96;, and &#96;sync&#96;. |
| [isBuiltinUserdata](#fn-state-isbuiltinuserdata) | `userdata: *const Userdata` | `bool` | True for userdata types implemented by the runtime, such as files. |
| [finalizeBuiltinUserdata](#fn-state-finalizebuiltinuserdata) | `self: *State, userdata: *Userdata` | `bool` | Runs the finalizer of a userdata type implemented by the runtime, which needs the state. Returns false for other userdata. |
| [closeFinalizerOrder](#fn-state-closefinalizerorder) | `userdata: *Userdata` | `?u64` |  |
| [builtinFinalizerOrder](#fn-state-builtinfinalizerorder) | `userdata: *Userdata` | `u64` | The creation order of runtime userdata, on the finalizer order scale. |
| [discard](#fn-state-discard) | `self: *State` | `void` |  |
| [deinit](#fn-state-deinit) | `self: *State` | `void` | Frees the state like &#96;lua_close&#96;: first calls every pending finalizer, running &#96;__gc&#96; metamethods and closing open files, newest first. The instruction budget restarts for each one. Discarded states, such as snapshot images, call none. |
| [deinitWithoutFinalizers](#fn-state-deinitwithoutfinalizers) | `self: *State` | `void` | Frees the state without calling Lua &#96;__gc&#96; metamethods, as a process exiting without &#96;lua_close&#96; does; open files are still flushed and closed. |
| [execute](#fn-state-execute) | `self: *State, proto: *proto_mod.Proto` | `!void` |  |
| [callLoadedClosure](#fn-state-callloadedclosure) | `self: *State, closure: *Closure, args: []const Value` | `![]Value` |  |
| [callLoadedClosureHandled](#fn-state-callloadedclosurehandled) | `self: *State, closure: *Closure, args: []const Value, handler: HostErrorHandler` | `![]Value` | Like &#96;callLoadedClosure&#96;; &#96;handler&#96; runs at the error point before frames unwind. |
| [protectedCallLoadedClosure](#fn-state-protectedcallloadedclosure) | `self: *State, closure: *Closure, args: []const Value` | `!ProtectedCallResult` |  |
| [protectedCallLoadedClosureHandled](#fn-state-protectedcallloadedclosurehandled) | `self: *State, closure: *Closure, args: []const Value, handler: HostErrorHandler` | `!ProtectedCallResult` | Like &#96;protectedCallLoadedClosure&#96;; &#96;handler&#96; runs at the error point before frames unwind. |
| [callFunction](#fn-state-callfunction) | `self: *State, function: Value, args: []const Value` | `![]Value` |  |
| [callFunctionHandled](#fn-state-callfunctionhandled) | `self: *State, function: Value, args: []const Value, handler: HostErrorHandler` | `![]Value` | Like &#96;callFunction&#96;; &#96;handler&#96; runs at the error point before frames unwind. |
| [protectedCallFunction](#fn-state-protectedcallfunction) | `self: *State, function: Value, args: []const Value` | `!ProtectedCallResult` |  |
| [protectedCallFunctionHandled](#fn-state-protectedcallfunctionhandled) | `self: *State, function: Value, args: []const Value, handler: HostErrorHandler` | `!ProtectedCallResult` | Like &#96;protectedCallFunction&#96;; &#96;handler&#96; runs at the error point before frames unwind. |
| [executeSourceChunk](#fn-state-executesourcechunk) | `self: *State, source: []const u8` | `!void` |  |
| [executeSourceChunkNamed](#fn-state-executesourcechunknamed) | `self: *State, source: []const u8, source_name: []const u8` | `!void` |  |
| [executeSourceChunkNamedHandled](#fn-state-executesourcechunknamedhandled) | `self: *State, source: []const u8, source_name: []const u8, handler: HostErrorHandler` | `!void` | Like &#96;executeSourceChunkNamed&#96;; &#96;handler&#96; runs at a runtime error point before frames unwind. |
| [noteCaughtError](#fn-state-notecaughterror) | `self: *State, err: anyerror` | `void` | Records the error for a Zig error caught from Lua execution: a stack overflow that has no message yet, or a memory error, which skips message handlers as in Lua. |
| [applyMessageHandler](#fn-state-applymessagehandler) | `self: *State, thread: *Thread` | `!void` | Runs the thread's message handler for the current error at the error point, like &#96;luaG_errormsg&#96;, unless the error already went through one. The handler runs on top of the live failing frames; an error in it is handled again on top of the handler's frames. The retries model Lua's C-call limit: the handler sees "C stack overflow" at &#96;LUAI_MAXCCALLS&#96; and the error becomes "error in error handling" a little later. |
| [pushNativeMark](#fn-state-pushnativemark) | `thread: *Thread, frame_count: usize, callee: Value` | `void` | Records a native function without a calling instruction for tracebacks. |
| [runThreadUntil](#fn-state-runthreaduntil) | `self: *State, thread: *Thread, target_frame_count: usize` | `anyerror!void` |  |
| [checkExecutionLimits](#fn-state-checkexecutionlimits) | `self: *State, thread: *Thread` | `!void` |  |
| [interruptControl](#fn-state-interruptcontrol) | `self: *State` | `!*vm_mod.InterruptControl` | Returns the interrupt control shared with host threads, allocating it on first use. Polling starts at the next safepoint. |
| [interruptRequested](#fn-state-interruptrequested) | `self: *const State` | `bool` | Reports a pending host interrupt. Safe to call on the owning thread at any time. |
| [clearInterrupt](#fn-state-clearinterrupt) | `self: *State` | `void` | Clears a pending interrupt request. |
| [checkInterrupt](#fn-state-checkinterrupt) | `self: *State` | `!void` | Raises &#96;error.Interrupted&#96; when a host interrupt is pending. Native functions with long internal loops call this periodically. |
| [instructionBudgetActive](#fn-state-instructionbudgetactive) | `self: *const State` | `bool` | True while any instruction budget applies; the uncounted fast loop is then disabled. |
| [instructionBudgetUsed](#fn-state-instructionbudgetused) | `self: *const State` | `u64` | Instructions counted against &#96;max_instructions&#96; since the last budget reset. |
| [resetInstructionBudget](#fn-state-resetinstructionbudget) | `self: *State` | `void` | Restarts the cumulative &#96;max_instructions&#96; budget. |
| [beginCallInstructionBudget](#fn-state-begincallinstructionbudget) | `self: *State, max: u64` | `?u64` | Narrows the instruction budget for a host call to at most &#96;max&#96; further instructions, including nested calls and coroutines. Returns the enclosing deadline for &#96;endCallInstructionBudget&#96;. |
| [endCallInstructionBudget](#fn-state-endcallinstructionbudget) | `self: *State, previous: ?u64` | `void` | Restores the deadline returned by &#96;beginCallInstructionBudget&#96;. |
| [noteAllocation](#fn-state-noteallocation) | `self: *State, bytes: usize` | `void` |  |
| [noteAllocationFreed](#fn-state-noteallocationfreed) | `self: *State, bytes: usize` | `void` |  |
| [refreshAllocationTotal](#fn-state-refreshallocationtotal) | `self: *State` | `usize` |  |
| [currentAllocationTotal](#fn-state-currentallocationtotal) | `self: *State` | `usize` |  |
| [tableCapacityBytes](#fn-state-tablecapacitybytes) | `table: *const Table` | `usize` |  |
| [tableGcBytes](#fn-state-tablegcbytes) | `table: *const Table` | `usize` |  |
| [noteTableCapacityDelta](#fn-state-notetablecapacitydelta) | `self: *State, table: *Table, old_capacity_bytes: usize` | `void` |  |
| [setTableRaw](#fn-state-settableraw) | `self: *State, table: *Table, key: Value, value: Value` | `!void` |  |
| [getGlobal](#fn-state-getglobal) | `self: *State, name: []const u8` | `Value` |  |
| [currentLine](#fn-state-currentline) | `self: *State, thread: *Thread, level: i64` | `?usize` |  |
| [currentExtraArgs](#fn-state-currentextraargs) | `self: *State, thread: *Thread, level: i64` | `?usize` |  |
| [currentWhat](#fn-state-currentwhat) | `self: *State, thread: *Thread, level: i64` | `[]const u8` |  |
| [currentFunctionName](#fn-state-currentfunctionname) | `self: *State, thread: *Thread, level: i64` | `?[]const u8` |  |
| [currentFunctionNameWhat](#fn-state-currentfunctionnamewhat) | `self: *State, thread: *Thread, level: i64` | `?[]const u8` |  |
| [setThreadHook](#fn-state-setthreadhook) | `self: *State, target: *Thread, hook: Value, mask: []const u8, count: u32` | `void` |  |
| [threadHookMask](#fn-state-threadhookmask) | `self: *State, thread: *Thread` | `![]const u8` |  |
| [callHook](#fn-state-callhook) | `self: *State, thread: *Thread, event: []const u8` | `!void` |  |
| [putGlobal](#fn-state-putglobal) | `self: *State, name: []const u8, value: Value` | `!void` |  |
| [rootValue](#fn-state-rootvalue) | `self: *State, value: Value` | `!usize` |  |
| [unrootValue](#fn-state-unrootvalue) | `self: *State, index: usize` | `void` |  |
| [rootedValue](#fn-state-rootedvalue) | `self: *const State, index: usize` | `Value` |  |
| [activeRootCount](#fn-state-activerootcount) | `self: State` | `usize` |  |
| [setApiCallbackDispatch](#fn-state-setapicallbackdispatch) | `self: *State, dispatch: ApiCallbackDispatchFn, user_data: *anyopaque` | `void` |  |
| [callApiCallbackDispatch](#fn-state-callapicallbackdispatch) | `self: *State, thread: *Thread, op: bytecode.Call, callback_id: usize` | `!void` |  |
| [readFileAlloc](#fn-state-readfilealloc) | `self: *State, path: []const u8` | `![]const u8` | Reads a whole file through the filesystem capability, limited by &#96;max_file_bytes&#96;. Failures raise PUC &#96;loadfile&#96;-style messages such as "cannot open name.lua: No such file or directory". |
| [readFileRaw](#fn-state-readfileraw) | `self: *State, path: []const u8` | `anyerror![]const u8` | Reads a whole file through the filesystem capability, limited by &#96;max_file_bytes&#96;, returning filesystem errors unchanged. |
| [failFileOperation](#fn-state-failfileoperation) | `self: *State, path: []const u8, err: anyerror` | `anyerror` | Raises "<path>: <strerror message>" for a failed file operation. |
| [writeStdout](#fn-state-writestdout) | `self: *State, bytes: []const u8` | `!void` |  |
| [warn](#fn-state-warn) | `self: *State, parts: []const []const u8` | `!void` | Emits one warning made of &#96;parts&#96;, like consecutive &#96;lua_warning&#96; calls that continue every part but the last. A single part starting with &#96;@&#96; is a control message: &#96;@on&#96; and &#96;@off&#96; switch warnings, and other controls are ignored. |
| [warnError](#fn-state-warnerror) | `self: *State, where: []const u8, error_value: Value` | `void` | Warns about an error caught where Lua cannot report it, like &#96;luaE_warnerror&#96;: &#96;error in <where> (<message>)&#96;. |
| [writeStderr](#fn-state-writestderr) | `self: *State, bytes: []const u8` | `!void` |  |
| [flushStdoutForInput](#fn-state-flushstdoutforinput) | `self: *State` | `void` | Before blocking on host stdin, flushes a line-buffered or unbuffered stdout writer, so interactive prompts appear as they do with C stdio. |
| [flushStdout](#fn-state-flushstdout) | `self: *State` | `!void` |  |
| [flushStderr](#fn-state-flushstderr) | `self: *State` | `!void` |  |
| [writeFile](#fn-state-writefile) | `self: *State, path: []const u8, data: []const u8` | `!void` |  |
| [removeFile](#fn-state-removefile) | `self: *State, path: []const u8` | `!void` |  |
| [renameFile](#fn-state-renamefile) | `self: *State, old_path: []const u8, new_path: []const u8` | `!void` |  |
| [fsReadFileAlloc](#fn-state-fsreadfilealloc) | `self: *State, path: []const u8, requested_max_bytes: usize` | `anyerror![]const u8` | Reads at most &#96;max_bytes&#96;, further capped by the state's &#96;max_file_bytes&#96;. |
| [fsWriteFile](#fn-state-fswritefile) | `self: *State, path: []const u8, data: []const u8` | `anyerror!void` |  |
| [fsCreateFileExclusive](#fn-state-fscreatefileexclusive) | `self: *State, path: []const u8` | `anyerror!void` | Creates an empty file, failing with &#96;error.PathAlreadyExists&#96; when the path exists, so the caller reserves the name like &#96;mkstemp&#96;. Host filesystems create exclusively; memory and callback filesystems check first, as they have no exclusive create. |
| [fsWriteFileAt](#fn-state-fswritefileat) | `self: *State, path: []const u8, offset: usize, data: []const u8` | `anyerror!void` | Writes &#96;data&#96; at &#96;offset&#96; of an existing file without truncating it, so buffered handles can flush only their unsynced suffix. Returns &#96;error.OperationUnsupported&#96; when the capability has no positional write; callers then rewrite the whole file with &#96;fsWriteFile&#96;. |
| [fsStat](#fn-state-fsstat) | `self: *State, path: []const u8, follow_symlinks: bool` | `anyerror!host.FileStat` |  |
| [fsReadDirAlloc](#fn-state-fsreaddiralloc) | `self: *State, path: []const u8` | `anyerror![]host.DirectoryEntry` |  |
| [fsMakeDir](#fn-state-fsmakedir) | `self: *State, path: []const u8, parents: bool` | `anyerror!void` |  |
| [fsRemovePath](#fn-state-fsremovepath) | `self: *State, path: []const u8, recursive: bool` | `anyerror!void` |  |
| [fsRenamePath](#fn-state-fsrenamepath) | `self: *State, old_path: []const u8, new_path: []const u8` | `anyerror!void` |  |
| [fsCopyFile](#fn-state-fscopyfile) | `self: *State, source: []const u8, destination: []const u8, overwrite: bool` | `anyerror!void` |  |
| [getenv](#fn-state-getenv) | `self: *State, name: []const u8` | `?[]const u8` |  |
| [currentTime](#fn-state-currenttime) | `self: *State` | `!i64` |  |
| [cpuTime](#fn-state-cputime) | `self: *State` | `!f64` | Processor time for &#96;os.clock&#96;, in seconds. A disabled or fixed clock reports 0. |
| [localOffset](#fn-state-localoffset) | `self: *State, timestamp: i64` | `!timezone.LocalOffset` | Local-time offset at a Unix timestamp. Clocks without a time zone use UTC. |
| [localToUtc](#fn-state-localtoutc) | `self: *State, local: i64, is_dst: ?bool` | `!i64` | Converts local wall-clock seconds to a Unix timestamp, like &#96;mktime&#96;. |
| [executeProcess](#fn-state-executeprocess) | `self: *State, command: []const u8` | `!ProcessResult` |  |
| [popenProcess](#fn-state-popenprocess) | `self: *State, command: []const u8, input: ?[]const u8` | `!host.PopenResult` | Runs a command for &#96;io.popen&#96;. Read mode (&#96;input == null&#96;) returns the command's stdout; write mode feeds &#96;input&#96; to its stdin. Other streams are inherited from the host process, like C &#96;popen&#96;. |
| [requestExit](#fn-state-requestexit) | `self: *State, code: i32, close: bool` | `!void` | Records an &#96;os.exit&#96; request. The caller unwinds with &#96;error.LuaExit&#96;. |
| [requireIo](#fn-state-requireio) | `self: *State, unavailable_message: []const u8` | `RuntimeError!std.Io` |  |
| [processEnabled](#fn-state-processenabled) | `self: *State` | `bool` |  |
| [StdinSource](#type-state-stdinsource) |  |  | Standard input shared by &#96;io.stdin&#96;, &#96;loadfile()&#96;, and &#96;debug.debug&#96;: the host &#96;stdin_reader&#96;, or the memory &#96;stdin&#96; bytes from &#96;stdin_pos&#96;. |
| [stdinSource](#fn-state-stdinsource) | `self: *State` | `StdinSource` | Callers read through &#96;reader()&#96; and then call &#96;finish()&#96;. |
| [stdinIsStream](#fn-state-stdinisstream) | `self: *const State` | `bool` |  |
| [loadSourceAsClosure](#fn-state-loadsourceasclosure) | `self: *State, source: []const u8` | `!Value` |  |
| [loadSourceAsClosureNamed](#fn-state-loadsourceasclosurenamed) | `self: *State, source: []const u8, source_name: ?[]const u8` | `!Value` |  |
| [loadSourceAsClosureNamedEnv](#fn-state-loadsourceasclosurenamedenv) | `self: *State, source: []const u8, source_name: ?[]const u8, environment: Value` | `!Value` |  |
| [loadBinaryDump](#fn-state-loadbinarydump) | `self: *State, source: []const u8, environment: Value` | `!Value` |  |
| [loadFileAsClosure](#fn-state-loadfileasclosure) | `self: *State, path: []const u8` | `!Value` |  |
| [loadFileAsClosureNamed](#fn-state-loadfileasclosurenamed) | `self: *State, path: []const u8, source_name: ?[]const u8` | `!Value` |  |
| [callCollect](#fn-state-callcollect) | `self: *State, thread: *Thread, callable: Value, args: []const Value` | `anyerror![]Value` |  |
| [intern](#fn-state-intern) | `self: *State, bytes: []const u8` | `![]const u8` |  |
| [allocateString](#fn-state-allocatestring) | `self: *State, bytes: []const u8` | `![]const u8` |  |
| [newTableWithHints](#fn-state-newtablewithhints) | `self: *State, array_hint: u32, hash_hint: u32` | `!Value` |  |
| [newUserdata](#fn-state-newuserdata) | `self: *State, ptr: *anyopaque, type_id: usize, type_name: []const u8, finalizer: ?UserdataFinalizer, finalizer_data: ?*const anyopaque, deinit_fn: ?UserdataDeinit` | `!Value` |  |
| [closeUpvalues](#fn-state-closeupvalues) | `self: *State, thread: *Thread, first_stack_index: usize` | `void` |  |
| [closeFramesTo](#fn-state-closeframesto) | `self: *State, thread: *Thread, frame_count: usize, error_value: ?Value` | `!void` |  |
| [getTableValue](#fn-state-gettablevalue) | `self: *State, table_value: Value, key_value: Value` | `!Value` |  |
| [getTableFromThread](#fn-state-gettablefromthread) | `self: *State, thread: *Thread, table_value: Value, key_value: Value` | `!Value` |  |
| [setTableValue](#fn-state-settablevalue) | `self: *State, table_value: Value, key_value: Value, value: Value` | `!void` |  |
| [setTableFromThread](#fn-state-settablefromthread) | `self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value` | `!void` |  |
| [lengthOf](#fn-state-lengthof) | `self: *State, thread: *Thread, value: Value` | `!Value` |  |
| [finishConcatRange](#fn-state-finishconcatrange) | `self: *State, thread: *Thread, dest: usize, first: usize, count_in: usize` | `!void` | Joins stack slots &#96;first..first+count&#96; right to left like PUC &#96;luaV_concat&#96;: each run of trailing strings and numbers becomes one string, and otherwise the last two operands go to &#96;__concat&#96;. Partial results stay in the operand slots so a yielding metamethod can resume. |
| [invokeValue](#fn-state-invokevalue) | `self: *State, thread: *Thread, resolved: bytecode.Call, depth: usize` | `anyerror!void` |  |
| [callOneResult](#fn-state-calloneresult) | `self: *State, thread: *Thread, callable: Value, args: []const Value` | `anyerror!Value` |  |
| [callOneResultWithContinuation](#fn-state-calloneresultwithcontinuation) | `self: *State, thread: *Thread, callable: Value, args: []const Value, result: CallOneContinuationResult` | `anyerror!Value` |  |
| [callOneMetamethodWithContinuation](#fn-state-callonemetamethodwithcontinuation) | `self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value, result: CallOneContinuationResult` | `anyerror!Value` |  |
| [callOneMetamethod](#fn-state-callonemetamethod) | `self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value` | `anyerror!Value` |  |
| [metamethodDebugName](#fn-state-metamethoddebugname) | `name: []const u8` | `[]const u8` |  |
| [callOneResultMaybeContinuation](#fn-state-calloneresultmaybecontinuation) | `self: *State, thread: *Thread, callable: Value, args: []const Value, continuation_result: ?CallOneContinuationResult` | `anyerror!Value` |  |
| [pushCallOneContinuation](#fn-state-pushcallonecontinuation) | `self: *State, thread: *Thread, frame_count: usize, result: CallOneContinuationResult` | `!void` |  |
| [readyCallOneContinuationIndex](#fn-state-readycallonecontinuationindex) | `thread: *Thread` | `?usize` |  |
| [completeReadyCallOneContinuation](#fn-state-completereadycallonecontinuation) | `self: *State, thread: *Thread` | `!bool` |  |
| [protectedCall](#fn-state-protectedcall) | `self: *State, thread: *Thread, callable: Value, args: []const Value` | `anyerror!ProtectedCallResult` |  |
| [protectedCallContext](#fn-state-protectedcallcontext) | `_: *State, thread: *Thread` | `ProtectedCallContext` |  |
| [protectedCallContextWithErrors](#fn-state-protectedcallcontextwitherrors) | `self: *State, thread: *Thread` | `ProtectedCallContext` |  |
| [runProtectedCall](#fn-state-runprotectedcall) | `self: *State, thread: *Thread, context: ProtectedCallContext, callable: Value, args: []const Value` | `anyerror!ProtectedCallResult` |  |
| [restoreProtectedCall](#fn-state-restoreprotectedcall) | `self: *State,         thread: *Thread,         context: ProtectedCallContext,         error_value: Value,` | `!Value` |  |
| [pushProtectedContinuation](#fn-state-pushprotectedcontinuation) | `self: *State, thread: *Thread, context: ProtectedCallContext, base: bytecode.Register, return_count: u16` | `!void` |  |
| [readyProtectedContinuationIndex](#fn-state-readyprotectedcontinuationindex) | `thread: *Thread` | `?usize` |  |
| [errorProtectedContinuationIndex](#fn-state-errorprotectedcontinuationindex) | `thread: *Thread` | `?usize` |  |
| [completeReadyProtectedContinuation](#fn-state-completereadyprotectedcontinuation) | `self: *State, thread: *Thread` | `!bool` |  |
| [completeProtectedContinuationError](#fn-state-completeprotectedcontinuationerror) | `self: *State, thread: *Thread` | `!bool` |  |
| [returnProtectedContinuationSuccess](#fn-state-returnprotectedcontinuationsuccess) | `self: *State, thread: *Thread, continuation: ProtectedContinuation, values: []Value` | `!void` |  |
| [returnProtectedContinuationFailure](#fn-state-returnprotectedcontinuationfailure) | `self: *State, thread: *Thread, continuation: ProtectedContinuation, failure: Value` | `!void` |  |
| [valueToString](#fn-state-valuetostring) | `self: *State, thread: *Thread, value: Value` | `anyerror![]const u8` |  |
| [rawMetatableValue](#fn-state-rawmetatablevalue) | `self: *State, value: Value` | `Value` | Returns a value's metatable without honoring &#96;__metatable&#96;, as &#96;debug.getmetatable&#96; does. |
| [setDebugMetatableValue](#fn-state-setdebugmetatablevalue) | `self: *State, value: Value, metatable_value: Value` | `!void` |  |
| [getMetamethod](#fn-state-getmetamethod) | `self: *State, value: Value, name: []const u8` | `!?Value` |  |
| [getMetaEvent](#fn-state-getmetaevent) | `self: *State, value: Value, event: types.MetaEvent` | `!?Value` | &#96;getMetamethod&#96; for a known event; metatables cache absent events. |
| [setTableMetatableRaw](#fn-state-settablemetatableraw) | `self: *State, table: *Table, metatable: ?*Table` | `void` |  |
| [checkUserdataFinalizer](#fn-state-checkuserdatafinalizer) | `self: *State, userdata: *Userdata` | `void` | Registers &#96;userdata&#96; for its metatable's &#96;__gc&#96;, like &#96;luaC_checkfinalizer&#96; when a metatable is set. File handles keep their built-in close for the file metatable's own &#96;__gc&#96;. |
| [nextFinalizerOrder](#fn-state-nextfinalizerorder) | `self: *State` | `u64` |  |
| [noteTableMetatableChanged](#fn-state-notetablemetatablechanged) | `self: *State, table: *Table, old_has_metatable: bool` | `void` |  |
| [unlinkTableMetatable](#fn-state-unlinktablemetatable) | `self: *State, table: *Table` | `void` |  |
| [luaTypeNameForError](#fn-state-luatypenameforerror) | `self: *State, value: Value` | `[]const u8` |  |
| [jumpIfBranchResult](#fn-state-jumpifbranchresult) | `self: *State, thread: *Thread, result: bool, jump_if_truthy: bool, offset: bytecode.JumpOffset` | `!void` |  |
| [compareValues](#fn-state-comparevalues) | `self: *State, thread: *Thread, lhs: Value, rhs: Value, op: CompareOp` | `!bool` |  |
| [returnValues](#fn-state-returnvalues) | `self: *State, thread: *Thread, base: bytecode.Register, return_count: u16, values: []const Value` | `!void` |  |
| [prepareClosureFrame](#fn-state-prepareclosureframe) | `self: *State, thread: *Thread, closure: *Closure, source_base: usize, frame_base: usize, arg_count: usize, return_start: usize, return_count: u16` | `!CallFrame` |  |
| [captureVarargs](#fn-state-capturevarargs) | `self: *State, thread: *Thread, source_start: usize, count: usize` | `![]const Value` |  |
| [namedVarargTable](#fn-state-namedvarargtable) | `self: *State, varargs: []const Value` | `!Value` |  |
| [resolveReturnCount](#fn-state-resolvereturncount) | `self: *State, count: u16, available: usize` | `!usize` |  |
| [caughtErrorValue](#fn-state-caughterrorvalue) | `self: *State, value: Value` | `!Value` | The error object Lua sees where an error is caught without a message handler: like &#96;luaG_errormsg&#96;, nil becomes &#96;<no error object>&#96;. |
| [tracebackMessageHandler](#fn-state-tracebackmessagehandler) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` | The standalone interpreter's message handler (&#96;msghandler&#96; in &#96;lua.c&#96;): adds a traceback to the error message, or reports an error object by its &#96;__tostring&#96; result or its type. |
| [snapshotCoroutineErrorTraceback](#fn-state-snapshotcoroutineerrortraceback) | `self: *State, target: *Thread` | `![]const u8` |  |
| [coroutineCreate](#fn-state-coroutinecreate) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [coroutineResume](#fn-state-coroutineresume) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [coroutineYield](#fn-state-coroutineyield) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [coroutineStatus](#fn-state-coroutinestatus) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [coroutineRunning](#fn-state-coroutinerunning) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [coroutineIsYieldable](#fn-state-coroutineisyieldable) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [coroutineClose](#fn-state-coroutineclose) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [coroutineWrap](#fn-state-coroutinewrap) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [callCoroutineWrapper](#fn-state-callcoroutinewrapper) | `self: *State, thread: *Thread, op: bytecode.Call, target: *Thread` | `!void` |  |
| [callCoroutineWrapperWithArgs](#fn-state-callcoroutinewrapperwithargs) | `self: *State, thread: *Thread, base: bytecode.Register, return_count: u16, target: *Thread, args: []const Value` | `!void` |  |
| [newCoroutineThread](#fn-state-newcoroutinethread) | `self: *State, entry: Value` | `!*Thread` |  |
| [closeCoroutine](#fn-state-closecoroutine) | `self: *State, target: *Thread, error_value: ?Value` | `!?Value` |  |
| [resumeCoroutine](#fn-state-resumecoroutine) | `self: *State, target: *Thread, args: []const Value` | `!CoroutineResumeResult` |  |
| [startCoroutine](#fn-state-startcoroutine) | `self: *State, target: *Thread, args: []const Value` | `!void` |  |
| [callableEntryClosure](#fn-state-callableentryclosure) | `self: *State` | `!*Closure` |  |
| [setCoroutineResumeValues](#fn-state-setcoroutineresumevalues) | `self: *State, target: *Thread, args: []const Value` | `!void` |  |
| [returnCoroutineResumeResult](#fn-state-returncoroutineresumeresult) | `self: *State, thread: *Thread, base: bytecode.Register, return_count: u16, result: CoroutineResumeResult` | `!void` |  |
| [copyValues](#fn-state-copyvalues) | `self: *State, values: []const Value` | `![]Value` |  |
| [copyStackSlice](#fn-state-copystackslice) | `self: *State, thread: *Thread, base: usize, count: usize` | `![]Value` |  |
| [collectArgs](#fn-state-collectargs) | `self: *State, thread: *Thread, op: bytecode.Call, first: u16` | `![]Value` |  |
| [returnProtectedResult](#fn-state-returnprotectedresult) | `self: *State, thread: *Thread, base: bytecode.Register, return_count: u16, result: ProtectedCallResult` | `!void` |  |
| [expectTable](#fn-state-expecttable) | `self: *State, value: Value` | `!*Table` |  |
| [expectString](#fn-state-expectstring) | `self: *State, value: Value` | `![]const u8` |  |
| [expectArgumentThread](#fn-state-expectargumentthread) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16` | `!*Thread` | &#96;getco&#96; in lcorolib: the coroutine argument of a &#96;coroutine&#96; function. |
| [expectThread](#fn-state-expectthread) | `self: *State, value: Value` | `!*Thread` |  |
| [collectGarbageValue](#fn-state-collectgarbagevalue) | `self: *State, thread: *Thread, op: bytecode.Call` | `!void` |  |
| [collectGarbageParam](#fn-state-collectgarbageparam) | `self: *State, value: Value` | `!GcParam` |  |
| [setGcMode](#fn-state-setgcmode) | `self: *State, mode: GcMode` | `GcMode` |  |
| [stepGc](#fn-state-stepgc) | `self: *State, steps: usize` | `!bool` |  |
| [normalizeGcBaseline](#fn-state-normalizegcbaseline) | `self: *State` | `void` |  |
| [collectGarbageStep](#fn-state-collectgarbagestep) | `self: *State, thread: ?*Thread, budget: i64` | `!bool` |  |
| [collectGarbage](#fn-state-collectgarbage) | `self: *State` | `!void` |  |
| [gcParam](#fn-state-gcparam) | `self: State, param: GcParam` | `i64` |  |
| [setGcParam](#fn-state-setgcparam) | `self: *State, param: GcParam, value: i64` | `void` |  |
| [collectGarbageConservatively](#fn-state-collectgarbageconservatively) | `self: *State, thread: ?*Thread` | `!void` |  |
| [collectGarbageWithFinalizers](#fn-state-collectgarbagewithfinalizers) | `self: *State, thread: ?*Thread` | `!void` |  |
| [collectGarbageWithFinalizersMode](#fn-state-collectgarbagewithfinalizersmode) | `self: *State, thread: ?*Thread, mark_all_stack_registers: bool` | `!void` |  |
| [shouldRunAutoGc](#fn-state-shouldrunautogc) | `self: *State` | `bool` |  |
| [resetAutoGcThreshold](#fn-state-resetautogcthreshold) | `self: *State` | `void` |  |
| [resetMarks](#fn-state-resetmarks) | `self: *State` | `void` |  |
| [markRoots](#fn-state-markroots) | `self: *State` | `void` |  |
| [markValue](#fn-state-markvalue) | `self: *State, value: Value` | `void` |  |
| [markRuntimeErrorPayload](#fn-state-markruntimeerrorpayload) | `self: *State, payload: ?RuntimeErrorPayload` | `void` |  |
| [markString](#fn-state-markstring) | `self: *State, bytes: []const u8` | `void` |  |
| [markTable](#fn-state-marktable) | `self: *State, table: *Table` | `void` |  |
| [markUserdata](#fn-state-markuserdata) | `self: *State, userdata: *Userdata` | `void` |  |
| [markWeakTableStrings](#fn-state-markweaktablestrings) | `self: *State, table: *Table, keys: bool, values: bool` | `void` |  |
| [markWeakString](#fn-state-markweakstring) | `self: *State, value: Value` | `void` |  |
| [markClosure](#fn-state-markclosure) | `self: *State, closure: *Closure` | `void` |  |
| [markUpvalue](#fn-state-markupvalue) | `self: *State, upvalue: *Upvalue` | `void` |  |
| [markThread](#fn-state-markthread) | `self: *State, thread: *Thread` | `void` |  |
| [markThreadStack](#fn-state-markthreadstack) | `self: *State, thread: *Thread` | `void` |  |
| [markStackRange](#fn-state-markstackrange) | `self: *State, thread: *Thread, base: usize, count: usize` | `void` |  |
| [weakMode](#fn-state-weakmode) | `self: *State, table: *Table` | `WeakMode` |  |
| [hasWeakTables](#fn-state-hasweaktables) | `self: *State` | `bool` |  |
| [markEphemeronValues](#fn-state-markephemeronvalues) | `self: *State, table: *Table` | `bool` |  |
| [convergeEphemerons](#fn-state-convergeephemerons) | `self: *State` | `void` |  |
| [markValueChanged](#fn-state-markvaluechanged) | `self: *State, value: Value` | `bool` |  |
| [valueIsMarked](#fn-state-valueismarked) | `self: *State, value: Value` | `bool` |  |
| [valueIsWeaklyCleared](#fn-state-valueisweaklycleared) | `self: *State, value: Value` | `bool` |  |
| [valueIsCollectableUnmarked](#fn-state-valueiscollectableunmarked) | `self: *State, value: Value` | `bool` |  |
| [clearWeakValues](#fn-state-clearweakvalues) | `self: *State` | `void` |  |
| [clearWeakTables](#fn-state-clearweaktables) | `self: *State` | `void` |  |
| [clearDeadHashKeys](#fn-state-cleardeadhashkeys) | `self: *State` | `void` |  |
| [clearWeakTableValues](#fn-state-clearweaktablevalues) | `self: *State, table: *Table` | `void` |  |
| [clearWeakTableKeys](#fn-state-clearweaktablekeys) | `self: *State, table: *Table` | `void` |  |
| [writeTableBarrier](#fn-state-writetablebarrier) | `self: *State, table: *Table, key: Value, value: Value` | `void` |  |
| [upvalueBarrier](#fn-state-upvaluebarrier) | `self: *State, closure: *Closure, upvalue: *Upvalue` | `void` |  |
| [threadBarrier](#fn-state-threadbarrier) | `self: *State, thread: *Thread, value: Value` | `void` |  |
| [writeBarrier](#fn-state-writebarrier) | `self: *State, parent: anytype, child: Value` | `void` |  |
| [runCloseFinalizers](#fn-state-runclosefinalizers) | `self: *State` | `void` | Provide a protected execution frame for GC requested by an idle host. Allocate it before consuming any pending registration so OOM is retryable. Calls every pending finalizer as &#96;deinit&#96; does, keeping the state. Later finalizer registrations are left for &#96;deinit&#96;. |
| [runFinalizersFromHost](#fn-state-runfinalizersfromhost) | `self: *State, limit: usize` | `anyerror!bool` |  |
| [runPendingFinalizers](#fn-state-runpendingfinalizers) | `self: *State, thread: ?*Thread` | `!void` |  |
| [runPendingUserdataFinalizers](#fn-state-runpendinguserdatafinalizers) | `self: *State` | `!void` |  |
| [callableValue](#fn-state-callablevalue) | `self: *State, value: Value` | `bool` |  |
| [sweepStrings](#fn-state-sweepstrings) | `self: *State` | `void` |  |
| [sweepUserdata](#fn-state-sweepuserdata) | `self: *State` | `void` |  |
| [sweepTables](#fn-state-sweeptables) | `self: *State` | `void` |  |
| [sweepClosures](#fn-state-sweepclosures) | `self: *State` | `void` |  |
| [sweepUpvalues](#fn-state-sweepupvalues) | `self: *State` | `void` |  |
| [sweepThreads](#fn-state-sweepthreads) | `self: *State` | `void` |  |
| [findStringAllocation](#fn-state-findstringallocation) | `self: *State, bytes: []const u8` | `?usize` |  |
| [isTrackedThread](#fn-state-istrackedthread) | `self: *State, thread: *Thread` | `bool` |  |
| [isTrackedTable](#fn-state-istrackedtable) | `self: *State, table: *Table` | `bool` |  |
| [isTrackedUserdata](#fn-state-istrackeduserdata) | `self: *State, userdata: *Userdata` | `bool` |  |
| [isTrackedClosure](#fn-state-istrackedclosure) | `self: *State, closure: *Closure` | `bool` |  |
| [isTrackedUpvalue](#fn-state-istrackedupvalue) | `self: *State, upvalue: *Upvalue` | `bool` |  |
| [destroyTable](#fn-state-destroytable) | `self: *State, table: *Table` | `void` |  |
| [destroyUserdata](#fn-state-destroyuserdata) | `self: *State, userdata: *Userdata` | `void` |  |
| [destroyClosure](#fn-state-destroyclosure) | `self: *State, closure: *Closure` | `void` |  |
| [destroyThread](#fn-state-destroythread) | `self: *State, thread: *Thread` | `void` |  |
| [allocationStats](#fn-state-allocationstats) | `self: State` | `RuntimeAllocationStats` |  |
| [failRuntimeDetail](#fn-state-failruntimedetail) | `self: *State, thread: ?*Thread, detail: []const u8` | `RuntimeError` |  |
| [errorDetailAlloc](#fn-state-errordetailalloc) | `self: *State, allocator: std.mem.Allocator, err: anyerror` | `![]const u8` |  |
| [fail](#fn-state-fail) | `self: *State, message: []const u8` | `RuntimeError` |  |
| [failArgument](#fn-state-failargument) | `self: *State, function_name: []const u8, index: u16, detail: errors.ArgumentErrorDetail` | `RuntimeError` | Raises &#96;bad argument #index to 'name' (detail)&#96; like &#96;luaL_argerror&#96;. &#96;index&#96; is the 1-based position among the native call's arguments; method calls renumber it and report a bad &#96;self&#96; as Lua does. The function is named from the calling instruction when Lua code made the call, else by a search of the loaded libraries, else &#96;function_name&#96;. |
| [failArgumentMessage](#fn-state-failargumentmessage) | `self: *State, function_name: []const u8, index: u16, message: []const u8` | `RuntimeError` |  |
| [failArgumentType](#fn-state-failargumenttype) | `self: *State, function_name: []const u8, index: u16, expected: []const u8, actual: Value` | `RuntimeError` |  |
| [failLibrary](#fn-state-faillibrary) | `self: *State, message: []const u8` | `RuntimeError` | Raises &#96;message&#96; like &#96;luaL_error&#96;: prefixed with the position of the Lua code that called the running library function, if any. |
| [withLibraryWhere](#fn-state-withlibrarywhere) | `self: *State, value: Value` | `!Value` | Prefixes a string error with &#96;luaL_where(L, 1)&#96;, as &#96;coroutine.wrap&#96; does for errors raised inside the coroutine. |
| [failLibraryFmt](#fn-state-faillibraryfmt) | `self: *State, comptime fmt: []const u8, args: anytype` | `RuntimeError` | &#96;failLibrary&#96; with a formatted message. |
| [appendGlobalFunctionName](#fn-state-appendglobalfunctionname) | `self: *State, out: *std.ArrayList(u8), callee: Value` | `!bool` | Mirrors &#96;pushglobalfuncname&#96;: finds &#96;callee&#96; as a global or as a field of a loaded module. |
| [expectArgumentString](#fn-state-expectargumentstring) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16` | `![]const u8` | &#96;luaL_checklstring&#96;: accepts strings and numbers. A number argument is converted in place, as Lua does, which also keeps the new string reachable for the rest of the call. |
| [optionalArgumentString](#fn-state-optionalargumentstring) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16` | `!?[]const u8` | &#96;luaL_optlstring&#96;: nil or an absent argument gives &#96;null&#96;. |
| [expectArgumentTable](#fn-state-expectargumenttable) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16` | `!*Table` |  |
| [argumentNumber](#fn-state-argumentnumber) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16` | `!f64` | &#96;luaL_checknumber&#96;. |
| [optionalArgumentInteger](#fn-state-optionalargumentinteger) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16, default: i64` | `!i64` | &#96;luaL_optinteger&#96;: nil or an absent argument gives &#96;default&#96;. |
| [argumentInteger](#fn-state-argumentinteger) | `self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16` | `!i64` | &#96;luaL_checkinteger&#96;. |
| [failValue](#fn-state-failvalue) | `self: *State, value: Value` | `RuntimeError` |  |
| [throwValue](#fn-state-throwvalue) | `self: *State, value: Value` | `RuntimeError` |  |
| [rethrowValue](#fn-state-rethrowvalue) | `self: *State, value: Value` | `RuntimeError` | Raises &#96;value&#96; again after closing variables for an error that already went through any message handler at its error point. |
| [currentErrorValue](#fn-state-currenterrorvalue) | `self: *State` | `Value` |  |

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

`fs` file handles share the `FILE*` metamethods, and their method table
adds `stat`, `tell`, `truncate`, `path`, and `sync`.

```zig
pub fn fsFileMetatable(state: *State) !*Table
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-isbuiltinuserdata"></a>

### State.isBuiltinUserdata

True for userdata types implemented by the runtime, such as files.

```zig
pub fn isBuiltinUserdata(userdata: *const Userdata) bool
```

References: [`Userdata`](#alias-userdata)

<a id="fn-state-finalizebuiltinuserdata"></a>

### State.finalizeBuiltinUserdata

Runs the finalizer of a userdata type implemented by the runtime, which
needs the state. Returns false for other userdata.

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

The creation order of runtime userdata, on the finalizer order scale.

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

Frees the state like `lua_close`: first calls every pending finalizer,
running `__gc` metamethods and closing open files, newest first. The
instruction budget restarts for each one. Discarded states, such as
snapshot images, call none.

```zig
pub fn deinit(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-deinitwithoutfinalizers"></a>

### State.deinitWithoutFinalizers

Frees the state without calling Lua `__gc` metamethods, as a process
exiting without `lua_close` does; open files are still flushed and closed.

```zig
pub fn deinitWithoutFinalizers(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-execute"></a>

### State.execute

```zig
pub fn execute(self: *State, proto: *proto_mod.Proto) !void
```

References: [`State`](#type-state)

<a id="fn-state-callloadedclosure"></a>

### State.callLoadedClosure

```zig
pub fn callLoadedClosure(self: *State, closure: *Closure, args: []const Value) ![]Value
```

References: [`State`](#type-state), [`Closure`](#alias-closure), [`Value`](#alias-value)

<a id="fn-state-callloadedclosurehandled"></a>

### State.callLoadedClosureHandled

Like `callLoadedClosure`; `handler` runs at the error point before frames unwind.

```zig
pub fn callLoadedClosureHandled(self: *State, closure: *Closure, args: []const Value, handler: HostErrorHandler) ![]Value
```

References: [`State`](#type-state), [`Closure`](#alias-closure), [`Value`](#alias-value), [`HostErrorHandler`](#type-hosterrorhandler)

<a id="fn-state-protectedcallloadedclosure"></a>

### State.protectedCallLoadedClosure

```zig
pub fn protectedCallLoadedClosure(self: *State, closure: *Closure, args: []const Value) !ProtectedCallResult
```

References: [`State`](#type-state), [`Closure`](#alias-closure), [`Value`](#alias-value), [`ProtectedCallResult`](#alias-protectedcallresult)

<a id="fn-state-protectedcallloadedclosurehandled"></a>

### State.protectedCallLoadedClosureHandled

Like `protectedCallLoadedClosure`; `handler` runs at the error point before frames unwind.

```zig
pub fn protectedCallLoadedClosureHandled(self: *State, closure: *Closure, args: []const Value, handler: HostErrorHandler) !ProtectedCallResult
```

References: [`State`](#type-state), [`Closure`](#alias-closure), [`Value`](#alias-value), [`HostErrorHandler`](#type-hosterrorhandler), [`ProtectedCallResult`](#alias-protectedcallresult)

<a id="fn-state-callfunction"></a>

### State.callFunction

```zig
pub fn callFunction(self: *State, function: Value, args: []const Value) ![]Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-callfunctionhandled"></a>

### State.callFunctionHandled

Like `callFunction`; `handler` runs at the error point before frames unwind.

```zig
pub fn callFunctionHandled(self: *State, function: Value, args: []const Value, handler: HostErrorHandler) ![]Value
```

References: [`State`](#type-state), [`Value`](#alias-value), [`HostErrorHandler`](#type-hosterrorhandler)

<a id="fn-state-protectedcallfunction"></a>

### State.protectedCallFunction

```zig
pub fn protectedCallFunction(self: *State, function: Value, args: []const Value) !ProtectedCallResult
```

References: [`State`](#type-state), [`Value`](#alias-value), [`ProtectedCallResult`](#alias-protectedcallresult)

<a id="fn-state-protectedcallfunctionhandled"></a>

### State.protectedCallFunctionHandled

Like `protectedCallFunction`; `handler` runs at the error point before frames unwind.

```zig
pub fn protectedCallFunctionHandled(self: *State, function: Value, args: []const Value, handler: HostErrorHandler) !ProtectedCallResult
```

References: [`State`](#type-state), [`Value`](#alias-value), [`HostErrorHandler`](#type-hosterrorhandler), [`ProtectedCallResult`](#alias-protectedcallresult)

<a id="fn-state-executesourcechunk"></a>

### State.executeSourceChunk

```zig
pub fn executeSourceChunk(self: *State, source: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-executesourcechunknamed"></a>

### State.executeSourceChunkNamed

```zig
pub fn executeSourceChunkNamed(self: *State, source: []const u8, source_name: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-executesourcechunknamedhandled"></a>

### State.executeSourceChunkNamedHandled

Like `executeSourceChunkNamed`; `handler` runs at a runtime error point before frames unwind.

```zig
pub fn executeSourceChunkNamedHandled(self: *State, source: []const u8, source_name: []const u8, handler: HostErrorHandler) !void
```

References: [`State`](#type-state), [`HostErrorHandler`](#type-hosterrorhandler)

<a id="fn-state-notecaughterror"></a>

### State.noteCaughtError

Records the error for a Zig error caught from Lua execution: a stack
overflow that has no message yet, or a memory error, which skips
message handlers as in Lua.

```zig
pub fn noteCaughtError(self: *State, err: anyerror) void
```

References: [`State`](#type-state)

<a id="fn-state-applymessagehandler"></a>

### State.applyMessageHandler

Runs the thread's message handler for the current error at the error
point, like `luaG_errormsg`, unless the error already went through
one. The handler runs on top of the live failing frames; an error in
it is handled again on top of the handler's frames. The retries model
Lua's C-call limit: the handler sees "C stack overflow" at
`LUAI_MAXCCALLS` and the error becomes "error in error handling" a
little later.

```zig
pub fn applyMessageHandler(self: *State, thread: *Thread) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-pushnativemark"></a>

### State.pushNativeMark

Records a native function without a calling instruction for tracebacks.

```zig
pub fn pushNativeMark(thread: *Thread, frame_count: usize, callee: Value) void
```

References: [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-runthreaduntil"></a>

### State.runThreadUntil

```zig
pub fn runThreadUntil(self: *State, thread: *Thread, target_frame_count: usize) anyerror!void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-checkexecutionlimits"></a>

### State.checkExecutionLimits

```zig
pub inline fn checkExecutionLimits(self: *State, thread: *Thread) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-interruptcontrol"></a>

### State.interruptControl

Returns the interrupt control shared with host threads, allocating it
on first use. Polling starts at the next safepoint.

```zig
pub fn interruptControl(self: *State) !*vm_mod.InterruptControl
```

References: [`State`](#type-state)

<a id="fn-state-interruptrequested"></a>

### State.interruptRequested

Reports a pending host interrupt. Safe to call on the owning thread at any time.

```zig
pub inline fn interruptRequested(self: *const State) bool
```

References: [`State`](#type-state)

<a id="fn-state-clearinterrupt"></a>

### State.clearInterrupt

Clears a pending interrupt request.

```zig
pub fn clearInterrupt(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-checkinterrupt"></a>

### State.checkInterrupt

Raises `error.Interrupted` when a host interrupt is pending. Native
functions with long internal loops call this periodically.

```zig
pub fn checkInterrupt(self: *State) !void
```

References: [`State`](#type-state)

<a id="fn-state-instructionbudgetactive"></a>

### State.instructionBudgetActive

True while any instruction budget applies; the uncounted fast loop is then disabled.

```zig
pub inline fn instructionBudgetActive(self: *const State) bool
```

References: [`State`](#type-state)

<a id="fn-state-instructionbudgetused"></a>

### State.instructionBudgetUsed

Instructions counted against `max_instructions` since the last budget reset.

```zig
pub fn instructionBudgetUsed(self: *const State) u64
```

References: [`State`](#type-state)

<a id="fn-state-resetinstructionbudget"></a>

### State.resetInstructionBudget

Restarts the cumulative `max_instructions` budget.

```zig
pub fn resetInstructionBudget(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-begincallinstructionbudget"></a>

### State.beginCallInstructionBudget

Narrows the instruction budget for a host call to at most `max`
further instructions, including nested calls and coroutines. Returns
the enclosing deadline for `endCallInstructionBudget`.

```zig
pub fn beginCallInstructionBudget(self: *State, max: u64) ?u64
```

References: [`State`](#type-state)

<a id="fn-state-endcallinstructionbudget"></a>

### State.endCallInstructionBudget

Restores the deadline returned by `beginCallInstructionBudget`.

```zig
pub fn endCallInstructionBudget(self: *State, previous: ?u64) void
```

References: [`State`](#type-state)

<a id="fn-state-noteallocation"></a>

### State.noteAllocation

```zig
pub fn noteAllocation(self: *State, bytes: usize) void
```

References: [`State`](#type-state)

<a id="fn-state-noteallocationfreed"></a>

### State.noteAllocationFreed

```zig
pub fn noteAllocationFreed(self: *State, bytes: usize) void
```

References: [`State`](#type-state)

<a id="fn-state-refreshallocationtotal"></a>

### State.refreshAllocationTotal

```zig
pub fn refreshAllocationTotal(self: *State) usize
```

References: [`State`](#type-state)

<a id="fn-state-currentallocationtotal"></a>

### State.currentAllocationTotal

```zig
pub fn currentAllocationTotal(self: *State) usize
```

References: [`State`](#type-state)

<a id="fn-state-tablecapacitybytes"></a>

### State.tableCapacityBytes

```zig
pub fn tableCapacityBytes(table: *const Table) usize
```

References: [`Table`](#alias-table)

<a id="fn-state-tablegcbytes"></a>

### State.tableGcBytes

```zig
pub fn tableGcBytes(table: *const Table) usize
```

References: [`Table`](#alias-table)

<a id="fn-state-notetablecapacitydelta"></a>

### State.noteTableCapacityDelta

```zig
pub fn noteTableCapacityDelta(self: *State, table: *Table, old_capacity_bytes: usize) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-settableraw"></a>

### State.setTableRaw

```zig
pub fn setTableRaw(self: *State, table: *Table, key: Value, value: Value) !void
```

References: [`State`](#type-state), [`Table`](#alias-table), [`Value`](#alias-value)

<a id="fn-state-getglobal"></a>

### State.getGlobal

```zig
pub fn getGlobal(self: *State, name: []const u8) Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-currentline"></a>

### State.currentLine

```zig
pub fn currentLine(self: *State, thread: *Thread, level: i64) ?usize
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-currentextraargs"></a>

### State.currentExtraArgs

```zig
pub fn currentExtraArgs(self: *State, thread: *Thread, level: i64) ?usize
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-currentwhat"></a>

### State.currentWhat

```zig
pub fn currentWhat(self: *State, thread: *Thread, level: i64) []const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-currentfunctionname"></a>

### State.currentFunctionName

```zig
pub fn currentFunctionName(self: *State, thread: *Thread, level: i64) ?[]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-currentfunctionnamewhat"></a>

### State.currentFunctionNameWhat

```zig
pub fn currentFunctionNameWhat(self: *State, thread: *Thread, level: i64) ?[]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-setthreadhook"></a>

### State.setThreadHook

```zig
pub fn setThreadHook(self: *State, target: *Thread, hook: Value, mask: []const u8, count: u32) void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-threadhookmask"></a>

### State.threadHookMask

```zig
pub fn threadHookMask(self: *State, thread: *Thread) ![]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-callhook"></a>

### State.callHook

```zig
pub fn callHook(self: *State, thread: *Thread, event: []const u8) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

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

<a id="fn-state-readfilealloc"></a>

### State.readFileAlloc

Reads a whole file through the filesystem capability, limited by
`max_file_bytes`. Failures raise PUC `loadfile`-style messages such as
"cannot open name.lua: No such file or directory".

```zig
pub fn readFileAlloc(self: *State, path: []const u8) ![]const u8
```

References: [`State`](#type-state)

<a id="fn-state-readfileraw"></a>

### State.readFileRaw

Reads a whole file through the filesystem capability, limited by
`max_file_bytes`, returning filesystem errors unchanged.

```zig
pub fn readFileRaw(self: *State, path: []const u8) anyerror![]const u8
```

References: [`State`](#type-state)

<a id="fn-state-failfileoperation"></a>

### State.failFileOperation

Raises "<path>: <strerror message>" for a failed file operation.

```zig
pub fn failFileOperation(self: *State, path: []const u8, err: anyerror) anyerror
```

References: [`State`](#type-state)

<a id="fn-state-writestdout"></a>

### State.writeStdout

```zig
pub fn writeStdout(self: *State, bytes: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-warn"></a>

### State.warn

Emits one warning made of `parts`, like consecutive `lua_warning`
calls that continue every part but the last. A single part starting
with `@` is a control message: `@on` and `@off` switch warnings, and
other controls are ignored.

```zig
pub fn warn(self: *State, parts: []const []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-warnerror"></a>

### State.warnError

Warns about an error caught where Lua cannot report it, like
`luaE_warnerror`: `error in <where> (<message>)`.

```zig
pub fn warnError(self: *State, where: []const u8, error_value: Value) void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-writestderr"></a>

### State.writeStderr

```zig
pub fn writeStderr(self: *State, bytes: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-flushstdoutforinput"></a>

### State.flushStdoutForInput

Before blocking on host stdin, flushes a line-buffered or unbuffered
stdout writer, so interactive prompts appear as they do with C stdio.

```zig
pub fn flushStdoutForInput(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-flushstdout"></a>

### State.flushStdout

```zig
pub fn flushStdout(self: *State) !void
```

References: [`State`](#type-state)

<a id="fn-state-flushstderr"></a>

### State.flushStderr

```zig
pub fn flushStderr(self: *State) !void
```

References: [`State`](#type-state)

<a id="fn-state-writefile"></a>

### State.writeFile

```zig
pub fn writeFile(self: *State, path: []const u8, data: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-removefile"></a>

### State.removeFile

```zig
pub fn removeFile(self: *State, path: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-renamefile"></a>

### State.renameFile

```zig
pub fn renameFile(self: *State, old_path: []const u8, new_path: []const u8) !void
```

References: [`State`](#type-state)

<a id="fn-state-fsreadfilealloc"></a>

### State.fsReadFileAlloc

Reads at most `max_bytes`, further capped by the state's `max_file_bytes`.

```zig
pub fn fsReadFileAlloc(self: *State, path: []const u8, requested_max_bytes: usize) anyerror![]const u8
```

References: [`State`](#type-state)

<a id="fn-state-fswritefile"></a>

### State.fsWriteFile

```zig
pub fn fsWriteFile(self: *State, path: []const u8, data: []const u8) anyerror!void
```

References: [`State`](#type-state)

<a id="fn-state-fscreatefileexclusive"></a>

### State.fsCreateFileExclusive

Creates an empty file, failing with `error.PathAlreadyExists` when the
path exists, so the caller reserves the name like `mkstemp`. Host
filesystems create exclusively; memory and callback filesystems check
first, as they have no exclusive create.

```zig
pub fn fsCreateFileExclusive(self: *State, path: []const u8) anyerror!void
```

References: [`State`](#type-state)

<a id="fn-state-fswritefileat"></a>

### State.fsWriteFileAt

Writes `data` at `offset` of an existing file without truncating it, so
buffered handles can flush only their unsynced suffix. Returns
`error.OperationUnsupported` when the capability has no positional
write; callers then rewrite the whole file with `fsWriteFile`.

```zig
pub fn fsWriteFileAt(self: *State, path: []const u8, offset: usize, data: []const u8) anyerror!void
```

References: [`State`](#type-state)

<a id="fn-state-fsstat"></a>

### State.fsStat

```zig
pub fn fsStat(self: *State, path: []const u8, follow_symlinks: bool) anyerror!host.FileStat
```

References: [`State`](#type-state)

<a id="fn-state-fsreaddiralloc"></a>

### State.fsReadDirAlloc

```zig
pub fn fsReadDirAlloc(self: *State, path: []const u8) anyerror![]host.DirectoryEntry
```

References: [`State`](#type-state)

<a id="fn-state-fsmakedir"></a>

### State.fsMakeDir

```zig
pub fn fsMakeDir(self: *State, path: []const u8, parents: bool) anyerror!void
```

References: [`State`](#type-state)

<a id="fn-state-fsremovepath"></a>

### State.fsRemovePath

```zig
pub fn fsRemovePath(self: *State, path: []const u8, recursive: bool) anyerror!void
```

References: [`State`](#type-state)

<a id="fn-state-fsrenamepath"></a>

### State.fsRenamePath

```zig
pub fn fsRenamePath(self: *State, old_path: []const u8, new_path: []const u8) anyerror!void
```

References: [`State`](#type-state)

<a id="fn-state-fscopyfile"></a>

### State.fsCopyFile

```zig
pub fn fsCopyFile(self: *State, source: []const u8, destination: []const u8, overwrite: bool) anyerror!void
```

References: [`State`](#type-state)

<a id="fn-state-getenv"></a>

### State.getenv

```zig
pub fn getenv(self: *State, name: []const u8) ?[]const u8
```

References: [`State`](#type-state)

<a id="fn-state-currenttime"></a>

### State.currentTime

```zig
pub fn currentTime(self: *State) !i64
```

References: [`State`](#type-state)

<a id="fn-state-cputime"></a>

### State.cpuTime

Processor time for `os.clock`, in seconds. A disabled or fixed clock reports 0.

```zig
pub fn cpuTime(self: *State) !f64
```

References: [`State`](#type-state)

<a id="fn-state-localoffset"></a>

### State.localOffset

Local-time offset at a Unix timestamp. Clocks without a time zone use UTC.

```zig
pub fn localOffset(self: *State, timestamp: i64) !timezone.LocalOffset
```

References: [`State`](#type-state)

<a id="fn-state-localtoutc"></a>

### State.localToUtc

Converts local wall-clock seconds to a Unix timestamp, like `mktime`.

```zig
pub fn localToUtc(self: *State, local: i64, is_dst: ?bool) !i64
```

References: [`State`](#type-state)

<a id="fn-state-executeprocess"></a>

### State.executeProcess

```zig
pub fn executeProcess(self: *State, command: []const u8) !ProcessResult
```

References: [`State`](#type-state), [`ProcessResult`](#alias-processresult)

<a id="fn-state-popenprocess"></a>

### State.popenProcess

Runs a command for `io.popen`. Read mode (`input == null`) returns the
command's stdout; write mode feeds `input` to its stdin. Other streams
are inherited from the host process, like C `popen`.

```zig
pub fn popenProcess(self: *State, command: []const u8, input: ?[]const u8) !host.PopenResult
```

References: [`State`](#type-state)

<a id="fn-state-requestexit"></a>

### State.requestExit

Records an `os.exit` request. The caller unwinds with `error.LuaExit`.

```zig
pub fn requestExit(self: *State, code: i32, close: bool) !void
```

References: [`State`](#type-state)

<a id="fn-state-requireio"></a>

### State.requireIo

```zig
pub fn requireIo(self: *State, unavailable_message: []const u8) RuntimeError!std.Io
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-processenabled"></a>

### State.processEnabled

```zig
pub fn processEnabled(self: *State) bool
```

References: [`State`](#type-state)

<a id="type-state-stdinsource"></a>

### State.StdinSource

Standard input shared by `io.stdin`, `loadfile()`, and `debug.debug`:
the host `stdin_reader`, or the memory `stdin` bytes from `stdin_pos`.

```zig
pub const StdinSource = struct {
    state: *State,
    fixed: std.Io.Reader,
    host: ?*std.Io.Reader,
};
```

#### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [reader](#fn-stdinsource-reader) | `self: *StdinSource` | `*std.Io.Reader` |  |
| [finish](#fn-stdinsource-finish) | `self: *StdinSource` | `void` | Records the memory bytes consumed through &#96;reader&#96;. |

<a id="fn-stdinsource-reader"></a>

#### StdinSource.reader

```zig
pub fn reader(self: *StdinSource) *std.Io.Reader
```

References: [`StdinSource`](#type-state-stdinsource)

<a id="fn-stdinsource-finish"></a>

#### StdinSource.finish

Records the memory bytes consumed through `reader`.

```zig
pub fn finish(self: *StdinSource) void
```

References: [`StdinSource`](#type-state-stdinsource)

<a id="fn-state-stdinsource"></a>

### State.stdinSource

Callers read through `reader()` and then call `finish()`.

```zig
pub fn stdinSource(self: *State) StdinSource
```

References: [`State`](#type-state), [`StdinSource`](#type-state-stdinsource)

<a id="fn-state-stdinisstream"></a>

### State.stdinIsStream

```zig
pub fn stdinIsStream(self: *const State) bool
```

References: [`State`](#type-state)

<a id="fn-state-loadsourceasclosure"></a>

### State.loadSourceAsClosure

```zig
pub fn loadSourceAsClosure(self: *State, source: []const u8) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-loadsourceasclosurenamed"></a>

### State.loadSourceAsClosureNamed

```zig
pub fn loadSourceAsClosureNamed(self: *State, source: []const u8, source_name: ?[]const u8) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-loadsourceasclosurenamedenv"></a>

### State.loadSourceAsClosureNamedEnv

```zig
pub fn loadSourceAsClosureNamedEnv(self: *State, source: []const u8, source_name: ?[]const u8, environment: Value) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-loadbinarydump"></a>

### State.loadBinaryDump

```zig
pub fn loadBinaryDump(self: *State, source: []const u8, environment: Value) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-loadfileasclosure"></a>

### State.loadFileAsClosure

```zig
pub fn loadFileAsClosure(self: *State, path: []const u8) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-loadfileasclosurenamed"></a>

### State.loadFileAsClosureNamed

```zig
pub fn loadFileAsClosureNamed(self: *State, path: []const u8, source_name: ?[]const u8) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-callcollect"></a>

### State.callCollect

```zig
pub fn callCollect(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror![]Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-intern"></a>

### State.intern

```zig
pub fn intern(self: *State, bytes: []const u8) ![]const u8
```

References: [`State`](#type-state)

<a id="fn-state-allocatestring"></a>

### State.allocateString

```zig
pub fn allocateString(self: *State, bytes: []const u8) ![]const u8
```

References: [`State`](#type-state)

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

<a id="fn-state-closeupvalues"></a>

### State.closeUpvalues

```zig
pub fn closeUpvalues(self: *State, thread: *Thread, first_stack_index: usize) void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-closeframesto"></a>

### State.closeFramesTo

```zig
pub fn closeFramesTo(self: *State, thread: *Thread, frame_count: usize, error_value: ?Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-gettablevalue"></a>

### State.getTableValue

```zig
pub fn getTableValue(self: *State, table_value: Value, key_value: Value) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-gettablefromthread"></a>

### State.getTableFromThread

```zig
pub fn getTableFromThread(self: *State, thread: *Thread, table_value: Value, key_value: Value) !Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-settablevalue"></a>

### State.setTableValue

```zig
pub fn setTableValue(self: *State, table_value: Value, key_value: Value, value: Value) !void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-settablefromthread"></a>

### State.setTableFromThread

```zig
pub fn setTableFromThread(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-lengthof"></a>

### State.lengthOf

```zig
pub fn lengthOf(self: *State, thread: *Thread, value: Value) !Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-finishconcatrange"></a>

### State.finishConcatRange

Joins stack slots `first..first+count` right to left like PUC
`luaV_concat`: each run of trailing strings and numbers becomes one
string, and otherwise the last two operands go to `__concat`. Partial
results stay in the operand slots so a yielding metamethod can resume.

```zig
pub fn finishConcatRange(self: *State, thread: *Thread, dest: usize, first: usize, count_in: usize) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-invokevalue"></a>

### State.invokeValue

```zig
pub fn invokeValue(self: *State, thread: *Thread, resolved: bytecode.Call, depth: usize) anyerror!void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-calloneresult"></a>

### State.callOneResult

```zig
pub fn callOneResult(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-calloneresultwithcontinuation"></a>

### State.callOneResultWithContinuation

```zig
pub fn callOneResultWithContinuation(self: *State, thread: *Thread, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-callonemetamethodwithcontinuation"></a>

### State.callOneMetamethodWithContinuation

```zig
pub fn callOneMetamethodWithContinuation(self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-callonemetamethod"></a>

### State.callOneMetamethod

```zig
pub fn callOneMetamethod(self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value) anyerror!Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-metamethoddebugname"></a>

### State.metamethodDebugName

```zig
pub fn metamethodDebugName(name: []const u8) []const u8
```

<a id="fn-state-calloneresultmaybecontinuation"></a>

### State.callOneResultMaybeContinuation

```zig
pub fn callOneResultMaybeContinuation(self: *State, thread: *Thread, callable: Value, args: []const Value, continuation_result: ?CallOneContinuationResult) anyerror!Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-pushcallonecontinuation"></a>

### State.pushCallOneContinuation

```zig
pub fn pushCallOneContinuation(self: *State, thread: *Thread, frame_count: usize, result: CallOneContinuationResult) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-readycallonecontinuationindex"></a>

### State.readyCallOneContinuationIndex

```zig
pub fn readyCallOneContinuationIndex(thread: *Thread) ?usize
```

References: [`Thread`](#alias-thread)

<a id="fn-state-completereadycallonecontinuation"></a>

### State.completeReadyCallOneContinuation

```zig
pub fn completeReadyCallOneContinuation(self: *State, thread: *Thread) !bool
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-protectedcall"></a>

### State.protectedCall

```zig
pub fn protectedCall(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!ProtectedCallResult
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value), [`ProtectedCallResult`](#alias-protectedcallresult)

<a id="fn-state-protectedcallcontext"></a>

### State.protectedCallContext

```zig
pub fn protectedCallContext(_: *State, thread: *Thread) ProtectedCallContext
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-protectedcallcontextwitherrors"></a>

### State.protectedCallContextWithErrors

```zig
pub fn protectedCallContextWithErrors(self: *State, thread: *Thread) ProtectedCallContext
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-runprotectedcall"></a>

### State.runProtectedCall

```zig
pub fn runProtectedCall(self: *State, thread: *Thread, context: ProtectedCallContext, callable: Value, args: []const Value) anyerror!ProtectedCallResult
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value), [`ProtectedCallResult`](#alias-protectedcallresult)

<a id="fn-state-restoreprotectedcall"></a>

### State.restoreProtectedCall

```zig
pub fn restoreProtectedCall(
        self: *State,
        thread: *Thread,
        context: ProtectedCallContext,
        error_value: Value,
    ) !Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-pushprotectedcontinuation"></a>

### State.pushProtectedContinuation

```zig
pub fn pushProtectedContinuation(self: *State, thread: *Thread, context: ProtectedCallContext, base: bytecode.Register, return_count: u16) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-readyprotectedcontinuationindex"></a>

### State.readyProtectedContinuationIndex

```zig
pub fn readyProtectedContinuationIndex(thread: *Thread) ?usize
```

References: [`Thread`](#alias-thread)

<a id="fn-state-errorprotectedcontinuationindex"></a>

### State.errorProtectedContinuationIndex

```zig
pub fn errorProtectedContinuationIndex(thread: *Thread) ?usize
```

References: [`Thread`](#alias-thread)

<a id="fn-state-completereadyprotectedcontinuation"></a>

### State.completeReadyProtectedContinuation

```zig
pub fn completeReadyProtectedContinuation(self: *State, thread: *Thread) !bool
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-completeprotectedcontinuationerror"></a>

### State.completeProtectedContinuationError

```zig
pub fn completeProtectedContinuationError(self: *State, thread: *Thread) !bool
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-returnprotectedcontinuationsuccess"></a>

### State.returnProtectedContinuationSuccess

```zig
pub fn returnProtectedContinuationSuccess(self: *State, thread: *Thread, continuation: ProtectedContinuation, values: []Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-returnprotectedcontinuationfailure"></a>

### State.returnProtectedContinuationFailure

```zig
pub fn returnProtectedContinuationFailure(self: *State, thread: *Thread, continuation: ProtectedContinuation, failure: Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-valuetostring"></a>

### State.valueToString

```zig
pub fn valueToString(self: *State, thread: *Thread, value: Value) anyerror![]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-rawmetatablevalue"></a>

### State.rawMetatableValue

Returns a value's metatable without honoring `__metatable`, as `debug.getmetatable` does.

```zig
pub fn rawMetatableValue(self: *State, value: Value) Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-setdebugmetatablevalue"></a>

### State.setDebugMetatableValue

```zig
pub fn setDebugMetatableValue(self: *State, value: Value, metatable_value: Value) !void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-getmetamethod"></a>

### State.getMetamethod

```zig
pub fn getMetamethod(self: *State, value: Value, name: []const u8) !?Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-getmetaevent"></a>

### State.getMetaEvent

`getMetamethod` for a known event; metatables cache absent events.

```zig
pub fn getMetaEvent(self: *State, value: Value, event: types.MetaEvent) !?Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-settablemetatableraw"></a>

### State.setTableMetatableRaw

```zig
pub fn setTableMetatableRaw(self: *State, table: *Table, metatable: ?*Table) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-checkuserdatafinalizer"></a>

### State.checkUserdataFinalizer

Registers `userdata` for its metatable's `__gc`, like
`luaC_checkfinalizer` when a metatable is set. [File](../stdlib/io.md#type-file) handles keep
their built-in close for the file metatable's own `__gc`.

```zig
pub fn checkUserdataFinalizer(self: *State, userdata: *Userdata) void
```

References: [`State`](#type-state), [`Userdata`](#alias-userdata)

<a id="fn-state-nextfinalizerorder"></a>

### State.nextFinalizerOrder

```zig
pub fn nextFinalizerOrder(self: *State) u64
```

References: [`State`](#type-state)

<a id="fn-state-notetablemetatablechanged"></a>

### State.noteTableMetatableChanged

```zig
pub fn noteTableMetatableChanged(self: *State, table: *Table, old_has_metatable: bool) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-unlinktablemetatable"></a>

### State.unlinkTableMetatable

```zig
pub fn unlinkTableMetatable(self: *State, table: *Table) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-luatypenameforerror"></a>

### State.luaTypeNameForError

```zig
pub fn luaTypeNameForError(self: *State, value: Value) []const u8
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-jumpifbranchresult"></a>

### State.jumpIfBranchResult

```zig
pub fn jumpIfBranchResult(self: *State, thread: *Thread, result: bool, jump_if_truthy: bool, offset: bytecode.JumpOffset) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-comparevalues"></a>

### State.compareValues

```zig
pub fn compareValues(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: CompareOp) !bool
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value), [`CompareOp`](#type-compareop)

<a id="fn-state-returnvalues"></a>

### State.returnValues

```zig
pub fn returnValues(self: *State, thread: *Thread, base: bytecode.Register, return_count: u16, values: []const Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-prepareclosureframe"></a>

### State.prepareClosureFrame

```zig
pub fn prepareClosureFrame(self: *State, thread: *Thread, closure: *Closure, source_base: usize, frame_base: usize, arg_count: usize, return_start: usize, return_count: u16) !CallFrame
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Closure`](#alias-closure)

<a id="fn-state-capturevarargs"></a>

### State.captureVarargs

```zig
pub fn captureVarargs(self: *State, thread: *Thread, source_start: usize, count: usize) ![]const Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-namedvarargtable"></a>

### State.namedVarargTable

```zig
pub fn namedVarargTable(self: *State, varargs: []const Value) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-resolvereturncount"></a>

### State.resolveReturnCount

```zig
pub fn resolveReturnCount(self: *State, count: u16, available: usize) !usize
```

References: [`State`](#type-state)

<a id="fn-state-caughterrorvalue"></a>

### State.caughtErrorValue

The error object Lua sees where an error is caught without a message
handler: like `luaG_errormsg`, nil becomes `<no error object>`.

```zig
pub fn caughtErrorValue(self: *State, value: Value) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-tracebackmessagehandler"></a>

### State.tracebackMessageHandler

The standalone interpreter's message handler (`msghandler` in
`lua.c`): adds a traceback to the error message, or reports an error
object by its `__tostring` result or its type.

```zig
pub fn tracebackMessageHandler(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-snapshotcoroutineerrortraceback"></a>

### State.snapshotCoroutineErrorTraceback

```zig
pub fn snapshotCoroutineErrorTraceback(self: *State, target: *Thread) ![]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-coroutinecreate"></a>

### State.coroutineCreate

```zig
pub fn coroutineCreate(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-coroutineresume"></a>

### State.coroutineResume

```zig
pub fn coroutineResume(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-coroutineyield"></a>

### State.coroutineYield

```zig
pub fn coroutineYield(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-coroutinestatus"></a>

### State.coroutineStatus

```zig
pub fn coroutineStatus(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-coroutinerunning"></a>

### State.coroutineRunning

```zig
pub fn coroutineRunning(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-coroutineisyieldable"></a>

### State.coroutineIsYieldable

```zig
pub fn coroutineIsYieldable(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-coroutineclose"></a>

### State.coroutineClose

```zig
pub fn coroutineClose(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-coroutinewrap"></a>

### State.coroutineWrap

```zig
pub fn coroutineWrap(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-callcoroutinewrapper"></a>

### State.callCoroutineWrapper

```zig
pub fn callCoroutineWrapper(self: *State, thread: *Thread, op: bytecode.Call, target: *Thread) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-callcoroutinewrapperwithargs"></a>

### State.callCoroutineWrapperWithArgs

```zig
pub fn callCoroutineWrapperWithArgs(self: *State, thread: *Thread, base: bytecode.Register, return_count: u16, target: *Thread, args: []const Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-newcoroutinethread"></a>

### State.newCoroutineThread

```zig
pub fn newCoroutineThread(self: *State, entry: Value) !*Thread
```

References: [`State`](#type-state), [`Value`](#alias-value), [`Thread`](#alias-thread)

<a id="fn-state-closecoroutine"></a>

### State.closeCoroutine

```zig
pub fn closeCoroutine(self: *State, target: *Thread, error_value: ?Value) !?Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-resumecoroutine"></a>

### State.resumeCoroutine

```zig
pub fn resumeCoroutine(self: *State, target: *Thread, args: []const Value) !CoroutineResumeResult
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-startcoroutine"></a>

### State.startCoroutine

```zig
pub fn startCoroutine(self: *State, target: *Thread, args: []const Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-callableentryclosure"></a>

### State.callableEntryClosure

```zig
pub fn callableEntryClosure(self: *State) !*Closure
```

References: [`State`](#type-state), [`Closure`](#alias-closure)

<a id="fn-state-setcoroutineresumevalues"></a>

### State.setCoroutineResumeValues

```zig
pub fn setCoroutineResumeValues(self: *State, target: *Thread, args: []const Value) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-returncoroutineresumeresult"></a>

### State.returnCoroutineResumeResult

```zig
pub fn returnCoroutineResumeResult(self: *State, thread: *Thread, base: bytecode.Register, return_count: u16, result: CoroutineResumeResult) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-copyvalues"></a>

### State.copyValues

```zig
pub fn copyValues(self: *State, values: []const Value) ![]Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-copystackslice"></a>

### State.copyStackSlice

```zig
pub fn copyStackSlice(self: *State, thread: *Thread, base: usize, count: usize) ![]Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-collectargs"></a>

### State.collectArgs

```zig
pub fn collectArgs(self: *State, thread: *Thread, op: bytecode.Call, first: u16) ![]Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-returnprotectedresult"></a>

### State.returnProtectedResult

```zig
pub fn returnProtectedResult(self: *State, thread: *Thread, base: bytecode.Register, return_count: u16, result: ProtectedCallResult) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`ProtectedCallResult`](#alias-protectedcallresult)

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

`getco` in lcorolib: the coroutine argument of a `coroutine` function.

```zig
pub fn expectArgumentThread(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16) !*Thread
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-expectthread"></a>

### State.expectThread

```zig
pub fn expectThread(self: *State, value: Value) !*Thread
```

References: [`State`](#type-state), [`Value`](#alias-value), [`Thread`](#alias-thread)

<a id="fn-state-collectgarbagevalue"></a>

### State.collectGarbageValue

```zig
pub fn collectGarbageValue(self: *State, thread: *Thread, op: bytecode.Call) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-collectgarbageparam"></a>

### State.collectGarbageParam

```zig
pub fn collectGarbageParam(self: *State, value: Value) !GcParam
```

References: [`State`](#type-state), [`Value`](#alias-value), [`GcParam`](#alias-gcparam)

<a id="fn-state-setgcmode"></a>

### State.setGcMode

```zig
pub fn setGcMode(self: *State, mode: GcMode) GcMode
```

References: [`State`](#type-state), [`GcMode`](#alias-gcmode)

<a id="fn-state-stepgc"></a>

### State.stepGc

```zig
pub fn stepGc(self: *State, steps: usize) !bool
```

References: [`State`](#type-state)

<a id="fn-state-normalizegcbaseline"></a>

### State.normalizeGcBaseline

```zig
pub fn normalizeGcBaseline(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-collectgarbagestep"></a>

### State.collectGarbageStep

```zig
pub fn collectGarbageStep(self: *State, thread: ?*Thread, budget: i64) !bool
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-collectgarbage"></a>

### State.collectGarbage

```zig
pub fn collectGarbage(self: *State) !void
```

References: [`State`](#type-state)

<a id="fn-state-gcparam"></a>

### State.gcParam

```zig
pub fn gcParam(self: State, param: GcParam) i64
```

References: [`State`](#type-state), [`GcParam`](#alias-gcparam)

<a id="fn-state-setgcparam"></a>

### State.setGcParam

```zig
pub fn setGcParam(self: *State, param: GcParam, value: i64) void
```

References: [`State`](#type-state), [`GcParam`](#alias-gcparam)

<a id="fn-state-collectgarbageconservatively"></a>

### State.collectGarbageConservatively

```zig
pub fn collectGarbageConservatively(self: *State, thread: ?*Thread) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-collectgarbagewithfinalizers"></a>

### State.collectGarbageWithFinalizers

```zig
pub fn collectGarbageWithFinalizers(self: *State, thread: ?*Thread) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-collectgarbagewithfinalizersmode"></a>

### State.collectGarbageWithFinalizersMode

```zig
pub fn collectGarbageWithFinalizersMode(self: *State, thread: ?*Thread, mark_all_stack_registers: bool) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-shouldrunautogc"></a>

### State.shouldRunAutoGc

```zig
pub fn shouldRunAutoGc(self: *State) bool
```

References: [`State`](#type-state)

<a id="fn-state-resetautogcthreshold"></a>

### State.resetAutoGcThreshold

```zig
pub fn resetAutoGcThreshold(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-resetmarks"></a>

### State.resetMarks

```zig
pub fn resetMarks(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-markroots"></a>

### State.markRoots

```zig
pub fn markRoots(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-markvalue"></a>

### State.markValue

```zig
pub fn markValue(self: *State, value: Value) void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-markruntimeerrorpayload"></a>

### State.markRuntimeErrorPayload

```zig
pub fn markRuntimeErrorPayload(self: *State, payload: ?RuntimeErrorPayload) void
```

References: [`State`](#type-state), [`RuntimeErrorPayload`](#alias-runtimeerrorpayload)

<a id="fn-state-markstring"></a>

### State.markString

```zig
pub fn markString(self: *State, bytes: []const u8) void
```

References: [`State`](#type-state)

<a id="fn-state-marktable"></a>

### State.markTable

```zig
pub fn markTable(self: *State, table: *Table) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-markuserdata"></a>

### State.markUserdata

```zig
pub fn markUserdata(self: *State, userdata: *Userdata) void
```

References: [`State`](#type-state), [`Userdata`](#alias-userdata)

<a id="fn-state-markweaktablestrings"></a>

### State.markWeakTableStrings

```zig
pub fn markWeakTableStrings(self: *State, table: *Table, keys: bool, values: bool) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-markweakstring"></a>

### State.markWeakString

```zig
pub fn markWeakString(self: *State, value: Value) void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-markclosure"></a>

### State.markClosure

```zig
pub fn markClosure(self: *State, closure: *Closure) void
```

References: [`State`](#type-state), [`Closure`](#alias-closure)

<a id="fn-state-markupvalue"></a>

### State.markUpvalue

```zig
pub fn markUpvalue(self: *State, upvalue: *Upvalue) void
```

References: [`State`](#type-state), [`Upvalue`](#alias-upvalue)

<a id="fn-state-markthread"></a>

### State.markThread

```zig
pub fn markThread(self: *State, thread: *Thread) void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-markthreadstack"></a>

### State.markThreadStack

```zig
pub fn markThreadStack(self: *State, thread: *Thread) void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-markstackrange"></a>

### State.markStackRange

```zig
pub fn markStackRange(self: *State, thread: *Thread, base: usize, count: usize) void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-weakmode"></a>

### State.weakMode

```zig
pub fn weakMode(self: *State, table: *Table) WeakMode
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-hasweaktables"></a>

### State.hasWeakTables

```zig
pub fn hasWeakTables(self: *State) bool
```

References: [`State`](#type-state)

<a id="fn-state-markephemeronvalues"></a>

### State.markEphemeronValues

```zig
pub fn markEphemeronValues(self: *State, table: *Table) bool
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-convergeephemerons"></a>

### State.convergeEphemerons

```zig
pub fn convergeEphemerons(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-markvaluechanged"></a>

### State.markValueChanged

```zig
pub fn markValueChanged(self: *State, value: Value) bool
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-valueismarked"></a>

### State.valueIsMarked

```zig
pub fn valueIsMarked(self: *State, value: Value) bool
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-valueisweaklycleared"></a>

### State.valueIsWeaklyCleared

```zig
pub fn valueIsWeaklyCleared(self: *State, value: Value) bool
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-valueiscollectableunmarked"></a>

### State.valueIsCollectableUnmarked

```zig
pub fn valueIsCollectableUnmarked(self: *State, value: Value) bool
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-clearweakvalues"></a>

### State.clearWeakValues

```zig
pub fn clearWeakValues(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-clearweaktables"></a>

### State.clearWeakTables

```zig
pub fn clearWeakTables(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-cleardeadhashkeys"></a>

### State.clearDeadHashKeys

```zig
pub fn clearDeadHashKeys(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-clearweaktablevalues"></a>

### State.clearWeakTableValues

```zig
pub fn clearWeakTableValues(self: *State, table: *Table) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-clearweaktablekeys"></a>

### State.clearWeakTableKeys

```zig
pub fn clearWeakTableKeys(self: *State, table: *Table) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-writetablebarrier"></a>

### State.writeTableBarrier

```zig
pub fn writeTableBarrier(self: *State, table: *Table, key: Value, value: Value) void
```

References: [`State`](#type-state), [`Table`](#alias-table), [`Value`](#alias-value)

<a id="fn-state-upvaluebarrier"></a>

### State.upvalueBarrier

```zig
pub fn upvalueBarrier(self: *State, closure: *Closure, upvalue: *Upvalue) void
```

References: [`State`](#type-state), [`Closure`](#alias-closure), [`Upvalue`](#alias-upvalue)

<a id="fn-state-threadbarrier"></a>

### State.threadBarrier

```zig
pub fn threadBarrier(self: *State, thread: *Thread, value: Value) void
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-state-writebarrier"></a>

### State.writeBarrier

```zig
pub fn writeBarrier(self: *State, parent: anytype, child: Value) void
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-runclosefinalizers"></a>

### State.runCloseFinalizers

Provide a protected execution frame for GC requested by an idle host.
Allocate it before consuming any pending registration so OOM is retryable.
Calls every pending finalizer as `deinit` does, keeping the state.
Later finalizer registrations are left for `deinit`.

```zig
pub fn runCloseFinalizers(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-runfinalizersfromhost"></a>

### State.runFinalizersFromHost

```zig
pub fn runFinalizersFromHost(self: *State, limit: usize) anyerror!bool
```

References: [`State`](#type-state)

<a id="fn-state-runpendingfinalizers"></a>

### State.runPendingFinalizers

```zig
pub fn runPendingFinalizers(self: *State, thread: ?*Thread) !void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-runpendinguserdatafinalizers"></a>

### State.runPendingUserdataFinalizers

```zig
pub fn runPendingUserdataFinalizers(self: *State) !void
```

References: [`State`](#type-state)

<a id="fn-state-callablevalue"></a>

### State.callableValue

```zig
pub fn callableValue(self: *State, value: Value) bool
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-sweepstrings"></a>

### State.sweepStrings

```zig
pub fn sweepStrings(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-sweepuserdata"></a>

### State.sweepUserdata

```zig
pub fn sweepUserdata(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-sweeptables"></a>

### State.sweepTables

```zig
pub fn sweepTables(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-sweepclosures"></a>

### State.sweepClosures

```zig
pub fn sweepClosures(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-sweepupvalues"></a>

### State.sweepUpvalues

```zig
pub fn sweepUpvalues(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-sweepthreads"></a>

### State.sweepThreads

```zig
pub fn sweepThreads(self: *State) void
```

References: [`State`](#type-state)

<a id="fn-state-findstringallocation"></a>

### State.findStringAllocation

```zig
pub fn findStringAllocation(self: *State, bytes: []const u8) ?usize
```

References: [`State`](#type-state)

<a id="fn-state-istrackedthread"></a>

### State.isTrackedThread

```zig
pub fn isTrackedThread(self: *State, thread: *Thread) bool
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-istrackedtable"></a>

### State.isTrackedTable

```zig
pub fn isTrackedTable(self: *State, table: *Table) bool
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-istrackeduserdata"></a>

### State.isTrackedUserdata

```zig
pub fn isTrackedUserdata(self: *State, userdata: *Userdata) bool
```

References: [`State`](#type-state), [`Userdata`](#alias-userdata)

<a id="fn-state-istrackedclosure"></a>

### State.isTrackedClosure

```zig
pub fn isTrackedClosure(self: *State, closure: *Closure) bool
```

References: [`State`](#type-state), [`Closure`](#alias-closure)

<a id="fn-state-istrackedupvalue"></a>

### State.isTrackedUpvalue

```zig
pub fn isTrackedUpvalue(self: *State, upvalue: *Upvalue) bool
```

References: [`State`](#type-state), [`Upvalue`](#alias-upvalue)

<a id="fn-state-destroytable"></a>

### State.destroyTable

```zig
pub fn destroyTable(self: *State, table: *Table) void
```

References: [`State`](#type-state), [`Table`](#alias-table)

<a id="fn-state-destroyuserdata"></a>

### State.destroyUserdata

```zig
pub fn destroyUserdata(self: *State, userdata: *Userdata) void
```

References: [`State`](#type-state), [`Userdata`](#alias-userdata)

<a id="fn-state-destroyclosure"></a>

### State.destroyClosure

```zig
pub fn destroyClosure(self: *State, closure: *Closure) void
```

References: [`State`](#type-state), [`Closure`](#alias-closure)

<a id="fn-state-destroythread"></a>

### State.destroyThread

```zig
pub fn destroyThread(self: *State, thread: *Thread) void
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-allocationstats"></a>

### State.allocationStats

```zig
pub fn allocationStats(self: State) RuntimeAllocationStats
```

References: [`State`](#type-state)

<a id="fn-state-failruntimedetail"></a>

### State.failRuntimeDetail

```zig
pub fn failRuntimeDetail(self: *State, thread: ?*Thread, detail: []const u8) RuntimeError
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-errordetailalloc"></a>

### State.errorDetailAlloc

```zig
pub fn errorDetailAlloc(self: *State, allocator: std.mem.Allocator, err: anyerror) ![]const u8
```

References: [`State`](#type-state)

<a id="fn-state-fail"></a>

### State.fail

```zig
pub fn fail(self: *State, message: []const u8) RuntimeError
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-failargument"></a>

### State.failArgument

Raises `bad argument #index to 'name' (detail)` like `luaL_argerror`.
`index` is the 1-based position among the native call's arguments;
method calls renumber it and report a bad `self` as Lua does. The
function is named from the calling instruction when Lua code made the
call, else by a search of the loaded libraries, else `function_name`.

```zig
pub fn failArgument(self: *State, function_name: []const u8, index: u16, detail: errors.ArgumentErrorDetail) RuntimeError
```

References: [`State`](#type-state), [`errors.ArgumentErrorDetail`](../errors.md#type-argumenterrordetail), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-failargumentmessage"></a>

### State.failArgumentMessage

```zig
pub fn failArgumentMessage(self: *State, function_name: []const u8, index: u16, message: []const u8) RuntimeError
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-failargumenttype"></a>

### State.failArgumentType

```zig
pub fn failArgumentType(self: *State, function_name: []const u8, index: u16, expected: []const u8, actual: Value) RuntimeError
```

References: [`State`](#type-state), [`Value`](#alias-value), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-faillibrary"></a>

### State.failLibrary

Raises `message` like `luaL_error`: prefixed with the position of
the Lua code that called the running library function, if any.

```zig
pub fn failLibrary(self: *State, message: []const u8) RuntimeError
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-withlibrarywhere"></a>

### State.withLibraryWhere

Prefixes a string error with `luaL_where(L, 1)`, as `coroutine.wrap`
does for errors raised inside the coroutine.

```zig
pub fn withLibraryWhere(self: *State, value: Value) !Value
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-faillibraryfmt"></a>

### State.failLibraryFmt

`failLibrary` with a formatted message.

```zig
pub fn failLibraryFmt(self: *State, comptime fmt: []const u8, args: anytype) RuntimeError
```

References: [`State`](#type-state), [`RuntimeError`](#alias-runtimeerror)

<a id="fn-state-appendglobalfunctionname"></a>

### State.appendGlobalFunctionName

Mirrors `pushglobalfuncname`: finds `callee` as a global or as a
field of a loaded module.

```zig
pub fn appendGlobalFunctionName(self: *State, out: *std.ArrayList(u8), callee: Value) !bool
```

References: [`State`](#type-state), [`Value`](#alias-value)

<a id="fn-state-expectargumentstring"></a>

### State.expectArgumentString

`luaL_checklstring`: accepts strings and numbers. A number argument is
converted in place, as Lua does, which also keeps the new string
reachable for the rest of the call.

```zig
pub fn expectArgumentString(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16) ![]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-optionalargumentstring"></a>

### State.optionalArgumentString

`luaL_optlstring`: nil or an absent argument gives `null`.

```zig
pub fn optionalArgumentString(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16) !?[]const u8
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-expectargumenttable"></a>

### State.expectArgumentTable

```zig
pub fn expectArgumentTable(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16) !*Table
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Table`](#alias-table)

<a id="fn-state-argumentnumber"></a>

### State.argumentNumber

`luaL_checknumber`.

```zig
pub fn argumentNumber(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16) !f64
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-optionalargumentinteger"></a>

### State.optionalArgumentInteger

`luaL_optinteger`: nil or an absent argument gives `default`.

```zig
pub fn optionalArgumentInteger(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16, default: i64) !i64
```

References: [`State`](#type-state), [`Thread`](#alias-thread)

<a id="fn-state-argumentinteger"></a>

### State.argumentInteger

`luaL_checkinteger`.

```zig
pub fn argumentInteger(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u16) !i64
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

Raises `value` again after closing variables for an error that
already went through any message handler at its error point.

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

<a id="type-compareop"></a>

## CompareOp

```zig
pub const CompareOp = enum {
    lt,
    le,
};
```

<a id="fn-luatypename"></a>

## luaTypeName

```zig
pub fn luaTypeName(value: Value) []const u8
```

References: [`Value`](#alias-value)

<a id="fn-valuesequal"></a>

## valuesEqual

```zig
pub fn valuesEqual(lhs: Value, rhs: Value) bool
```

References: [`Value`](#alias-value)

<a id="fn-truthy"></a>

## truthy

```zig
pub fn truthy(value: Value) bool
```

References: [`Value`](#alias-value)

<a id="fn-tointeger"></a>

## toInteger

```zig
pub fn toInteger(value: Value) ?i64
```

References: [`Value`](#alias-value)

<a id="fn-tonumber"></a>

## toNumber

```zig
pub fn toNumber(value: Value) !f64
```

References: [`Value`](#alias-value)

<a id="fn-appendluastring"></a>

## appendLuaString

```zig
pub fn appendLuaString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void
```

References: [`Value`](#alias-value)

<a id="fn-localactiveat"></a>

## localActiveAt

```zig
pub fn localActiveAt(local: proto_mod.LocalDebug, pc: usize) bool
```

<a id="fn-parseintegerstrict"></a>

## parseIntegerStrict

```zig
pub fn parseIntegerStrict(text: []const u8) ?i64
```

<a id="fn-parseluanumber"></a>

## parseLuaNumber

```zig
pub fn parseLuaNumber(text: []const u8) !f64
```

<a id="fn-floattointeger"></a>

## floatToInteger

```zig
pub fn floatToInteger(number: f64) ?i64
```

<a id="fn-trimascii"></a>

## trimAscii

```zig
pub fn trimAscii(text: []const u8) []const u8
```

<a id="fn-runtimeargvalue"></a>

## runtimeArgValue

```zig
pub fn runtimeArgValue(state: *State, thread: *Thread, op: bytecode.Call, index: u16) Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-argvalue"></a>

## argValue

```zig
pub fn argValue(state: *State, thread: *Thread, op: bytecode.Call, index: u16) Value
```

References: [`State`](#type-state), [`Thread`](#alias-thread), [`Value`](#alias-value)

<a id="fn-appenderrorvalue"></a>

## appendErrorValue

Formats a value without metamethods. [File](../stdlib/io.md#type-file) handles format like their
`__tostring`, as a Lua error object that is a file does.
Appends an error object like `appendValue`, describing a nil error
object as `<no error object>`, the message Lua substitutes for it.

```zig
pub fn appendErrorValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void
```

References: [`Value`](#alias-value)

<a id="fn-appendvalue"></a>

## appendValue

```zig
pub fn appendValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void
```

References: [`Value`](#alias-value)

<a id="fn-isfilevalue"></a>

## isFileValue

True for `FILE*` userdata from the io library.

```zig
pub fn isFileValue(value: Value) bool
```

References: [`Value`](#alias-value)

<a id="fn-isclosedfilevalue"></a>

## isClosedFileValue

```zig
pub fn isClosedFileValue(value: Value) bool
```

References: [`Value`](#alias-value)

<a id="fn-appendnumber"></a>

## appendNumber

```zig
pub fn appendNumber(allocator: std.mem.Allocator, out: *std.ArrayList(u8), number: f64) !void
```

<a id="fn-appendfmt"></a>

## appendFmt

```zig
pub fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void
```

