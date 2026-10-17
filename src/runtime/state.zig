const std = @import("std");
const rollback_mod = @import("rollback.zig");
const builtin = @import("builtin");
const compile = @import("../compile.zig");
const call_mod = @import("call.zig");
const coroutine_mod = @import("coroutine.zig");
const debug_mod = @import("debug.zig");
const chunk_mod = @import("chunk.zig");
const errors = @import("../errors.zig");
const frontend = @import("../frontend.zig");
const gc_mod = @import("gc.zig");
const host = @import("host.zig");
const timezone = @import("timezone.zig");
const stdlib = @import("../stdlib.zig");
const stdlib_static_strings = @import("../stdlib/static_strings.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const value_mod = @import("value.zig");

const bytecode = compile.bytecode;
const proto_mod = compile.proto;
const Clock = std.Io.Clock;
const Dir = std.Io.Dir;

pub const RuntimeError = types.RuntimeError;

const default_max_stack_values: usize = 1_000_000;
const default_max_call_frames: usize = 1_000_000;
const lua_max_c_calls: usize = 200;
const stack_error_frames: usize = 32;
const stack_error_values: usize = 200;
const max_metamethod_depth: usize = 15;

pub const Value = types.Value;
pub const NativeFn = types.NativeFn;
pub const UserdataFinalizer = types.UserdataFinalizer;
pub const UserdataDeinit = types.UserdataDeinit;
pub const ProtectedCallResult = types.ProtectedCallResult;
pub const ApiCallbackDispatchFn = types.ApiCallbackDispatchFn;
pub const ApiCallbackContext = types.ApiCallbackContext;
pub const RuntimeErrorPayload = types.RuntimeErrorPayload;
const ProtectedCallContext = types.ProtectedCallContext;
const ProtectedContinuation = types.ProtectedContinuation;
const GenericForContinuation = types.GenericForContinuation;
const BranchContinuation = types.BranchContinuation;
const TailCallContinuation = types.TailCallContinuation;
const CallOneContinuationResult = types.CallOneContinuationResult;
const CallOneContinuation = types.CallOneContinuation;
const BinaryChunkReader = chunk_mod.BinaryChunkReader(State);

const binary_chunk_payload_magic = chunk_mod.binary_chunk_payload_magic;
const appendBinaryChunkHeader = chunk_mod.appendBinaryChunkHeader;

pub const StdlibMode = stdlib.LibrarySelection;
pub const MemoryFile = host.MemoryFile;
pub const MemoryFilesystem = host.MemoryFilesystem;
pub const FilesystemCapability = host.FilesystemCapability;
pub const HostDirectory = host.HostDirectory;
pub const FilesystemFileKind = host.FileKind;
pub const FilesystemFileStat = host.FileStat;
pub const FilesystemDirectoryEntry = host.DirectoryEntry;
pub const EnvironmentCapability = host.EnvironmentCapability;
pub const ClockCapability = host.ClockCapability;
pub const ProcessCapability = host.ProcessCapability;
pub const ProcessResult = host.ProcessResult;

const CoroutineResumeResult = types.CoroutineResumeResult;
pub const Closure = types.Closure;
pub const Upvalue = types.Upvalue;
const TableEntry = types.TableEntry;
const TableEntryIndex = types.TableEntryIndex;
pub const Table = types.Table;
pub const Userdata = types.Userdata;
pub const Thread = types.Thread;
const ThreadStatus = types.ThreadStatus;
const CallFrame = types.CallFrame;
const StringAllocation = types.StringAllocation;
const PointerAllocationIndex = types.PointerAllocationIndex;
pub const GcMode = types.GcMode;
pub const GcParam = types.GcParam;
const GcParams = types.GcParams;
const WeakMode = types.WeakMode;
const RuntimeAllocationStats = types.RuntimeAllocationStats;

pub const StartupPhase = enum {
    state,
    globals,
    libraries,
    gc_baseline,
};

/// When stdout/stderr writers flush, beyond `io.flush`, `file:flush`, `os.exit`,
/// and before `os.execute`/`io.popen` start a child process.
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

/// Handles a runtime error escaping a host entry point. Runs at the error point,
/// before the failing frames unwind or `__close` runs.
pub const HostErrorHandler = struct {
    /// Lua message handler with `xpcall` semantics.
    message_handler: Value = .nil,
    /// Receives a traceback the caller frees with the state allocator.
    traceback: ?*?[]u8 = null,
    /// End the traceback with `[C]: in ?`, as `lua.c` does.
    host_frame: bool = false,
};

pub const State = struct {
    pub const max_c_calls = lua_max_c_calls;
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
    zerde_null: ?*Table = null,
    zerde_array_metatable: ?*Table = null,
    zerde_object_metatable: ?*Table = null,
    is_collecting: bool = false,
    stress_collect: bool = false,
    stress_step: bool = false,
    stress_mark: usize = 0,
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
    instruction_count: u64 = 0,
    /// `instruction_count` at the last budget reset.
    instruction_budget_base: u64 = 0,
    /// Deadline of the innermost budgeted host call, narrowed by enclosing ones.
    call_instruction_deadline: ?u64 = null,
    /// `instruction_count` at which `vm.executionCheckpoint` runs; zero forces a recompute.
    instruction_checkpoint: u64 = 0,
    /// Allocated on first use.
    interrupt: ?*vm_mod.InterruptControl = null,

    pub fn registerAllocation(self: *State, comptime field: []const u8, item: anytype) !void {
        if (self.rollback) |journal| try journal.prepareAllocation(self);
        try gc_mod.prepareRegistration(State, self, field);
        try @field(self, field).append(self.allocator, item);
        gc_mod.registeredAllocation(State, self, field, item);
        if (self.rollback) |journal| journal.allocated(field, item);
    }

    pub fn init(allocator: std.mem.Allocator) !State {
        return initWithOptions(allocator, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, options: StateOptions) !State {
        const NoopObserver = struct {
            fn observe(_: void, _: StartupPhase, _: *State) void {}
        };
        return initWithOptionsObserved(allocator, options, {}, NoopObserver.observe);
    }

    pub fn initWithOptionsObserved(
        allocator: std.mem.Allocator,
        options: StateOptions,
        observer_context: anytype,
        comptime observe: anytype,
    ) !State {
        var state = State{
            .allocator = allocator,
            .strings = std.StringHashMap([]const u8).init(allocator),
            .string_allocation_index = PointerAllocationIndex.init(allocator),
            .table_allocation_index = PointerAllocationIndex.init(allocator),
            .options = options,
            .warnings_on = options.warnings,
        };
        errdefer state.deinit();

        const hints = stdlib.initHints(options.stdlib);
        try state.strings.ensureTotalCapacity(@intCast(hints.strings));
        try state.string_allocations.ensureTotalCapacity(allocator, hints.strings);
        try state.string_allocation_index.ensureTotalCapacity(@intCast(hints.strings));
        try state.table_allocations.ensureTotalCapacity(allocator, hints.tables);
        try state.table_allocation_index.ensureTotalCapacity(@intCast(hints.tables));
        observe(observer_context, .state, &state);

        try stdlib.installGlobalTableWithHint(&state, hints.globals);
        observe(observer_context, .globals, &state);

        try stdlib.openLibraries(&state, options.stdlib);
        observe(observer_context, .libraries, &state);

        _ = state.refreshAllocationTotal();
        gc_mod.normalizeBaseline(State, &state);
        observe(observer_context, .gc_baseline, &state);
        return state;
    }

    pub fn stackValueLimit(self: *const State) usize {
        return if (self.options.max_stack_values) |limit| @min(limit, default_max_stack_values) else default_max_stack_values;
    }

    fn stressPending(self: *const State) bool {
        return (self.stress_collect or self.stress_step) and self.gc_known_total != self.stress_mark;
    }

    pub fn callFrameLimit(self: *const State) usize {
        return if (self.options.max_call_frames) |limit| @min(limit, default_max_call_frames) else default_max_call_frames;
    }

    pub fn fileMetatable(state: *State) !*Table {
        if (state.file_metatable) |metatable| return metatable;

        const metatable = (try state.newTableWithHints(0, 5)).table;
        state.file_metatable = metatable;
        errdefer state.file_metatable = null;
        const methods = try state.newTableWithHints(0, 7);
        try state.setTableRaw(metatable, .{ .string = stdlib_static_strings.get("__index") }, methods);
        try state.setTableRaw(metatable, .{ .string = stdlib_static_strings.get("__name") }, .{ .string = stdlib_static_strings.get("FILE*") });
        try state.setTableRaw(metatable, .{ .string = stdlib_static_strings.get("__tostring") }, .{ .native = .io_file_tostring });
        try state.setTableRaw(metatable, .{ .string = stdlib_static_strings.get("__close") }, .{ .native = .io_file_gc });
        try state.setTableRaw(metatable, .{ .string = stdlib_static_strings.get("__gc") }, .{ .native = .io_file_gc });
        try setFileMethods(state, methods.table);
        return metatable;
    }

    /// Extends the `FILE*` metatable with `stat`, `tell`, `truncate`, `path`, and `sync`.
    pub fn fsFileMetatable(state: *State) !*Table {
        if (state.fs_file_metatable) |metatable| return metatable;
        const file_metatable = try state.fileMetatable();
        const metatable = (try state.newTableWithHints(0, 5)).table;
        state.fs_file_metatable = metatable;
        errdefer state.fs_file_metatable = null;
        for (file_metatable.entries.items) |entry| {
            if (entry.value != .nil) try state.setTableRaw(metatable, entry.key, entry.value);
        }
        const methods = try state.newTableWithHints(0, 12);
        try state.setTableRaw(metatable, .{ .string = stdlib_static_strings.get("__index") }, methods);
        try setFileMethods(state, methods.table);
        try state.setTableRaw(methods.table, .{ .string = try state.intern("stat") }, .{ .native = .fs_file_stat });
        try state.setTableRaw(methods.table, .{ .string = try state.intern("tell") }, .{ .native = .fs_file_tell });
        try state.setTableRaw(methods.table, .{ .string = try state.intern("truncate") }, .{ .native = .fs_file_truncate });
        try state.setTableRaw(methods.table, .{ .string = stdlib_static_strings.get("path") }, .{ .native = .fs_file_path });
        try state.setTableRaw(methods.table, .{ .string = try state.intern("sync") }, .{ .native = .io_file_flush });
        return metatable;
    }

    fn setFileMethods(state: *State, methods: *Table) !void {
        try state.setTableRaw(methods, .{ .string = stdlib_static_strings.get("read") }, .{ .native = .io_file_read });
        try state.setTableRaw(methods, .{ .string = stdlib_static_strings.get("write") }, .{ .native = .io_file_write });
        try state.setTableRaw(methods, .{ .string = stdlib_static_strings.get("close") }, .{ .native = .io_file_close });
        try state.setTableRaw(methods, .{ .string = stdlib_static_strings.get("seek") }, .{ .native = .io_file_seek });
        try state.setTableRaw(methods, .{ .string = stdlib_static_strings.get("flush") }, .{ .native = .io_file_flush });
        try state.setTableRaw(methods, .{ .string = stdlib_static_strings.get("lines") }, .{ .native = .io_file_lines });
        try state.setTableRaw(methods, .{ .string = stdlib_static_strings.get("setvbuf") }, .{ .native = .io_file_setvbuf });
    }

    pub fn isBuiltinUserdata(userdata: *const Userdata) bool {
        return userdata.type_id == stdlib.io.fileTypeId();
    }

    /// Returns false for userdata not implemented by the runtime.
    pub fn finalizeBuiltinUserdata(self: *State, userdata: *Userdata) bool {
        if (!isBuiltinUserdata(userdata)) return false;
        stdlib.io.finalizeFile(self, userdata);
        return true;
    }

    pub fn closeFinalizerOrder(userdata: *Userdata) ?u64 {
        return stdlib.io.closeFinalizerOrder(userdata);
    }

    pub fn builtinFinalizerOrder(userdata: *Userdata) u64 {
        return stdlib.io.fileOf(.{ .userdata = userdata }).?.finalizer_order;
    }

    pub fn discard(self: *State) void {
        self.discarding = true;
        self.deinit();
    }

    /// Like `lua_close`: runs pending finalizers newest first, restarting the
    /// instruction budget for each, then frees the state.
    pub fn deinit(self: *State) void {
        self.deinitClosing(true);
    }

    /// Skips Lua `__gc` metamethods, like exiting without `lua_close`; open files are still closed.
    pub fn deinitWithoutFinalizers(self: *State) void {
        self.deinitClosing(false);
    }

    fn deinitClosing(self: *State, run_finalizers: bool) void {
        if (self.rollback) |journal| journal.abandon(self);
        if (!self.discarding) {
            if (run_finalizers) self.runCloseFinalizers();
            stdlib.io.closeOpenFiles(self);
        }
        self.snapshot_busy = true;
        if (self.local_zone) |zone| {
            zone.deinit();
            self.allocator.destroy(zone);
        }
        if (self.interrupt) |control| self.allocator.destroy(control);
        self.stdout.deinit(self.allocator);
        self.stderr.deinit(self.allocator);
        self.strings.deinit();
        self.string_allocation_index.deinit();
        self.table_allocation_index.deinit();
        self.object_allocation_index.deinit(self.allocator);
        self.gc_work.deinit(self.allocator);
        self.gc_remembered.deinit(self.allocator);
        self.gc_weak.deinit(self.allocator);
        self.gc_tables.deinit(self.allocator);
        self.gc_finalizers.deinit(self.allocator);
        for (self.thread_allocations.items) |thread| self.destroyThread(thread);
        for (self.closure_allocations.items) |closure| self.destroyClosure(closure);
        for (self.upvalue_allocations.items) |upvalue| self.allocator.destroy(upvalue);
        for (self.userdata_allocations.items) |userdata| self.destroyUserdata(userdata);
        for (self.table_allocations.items) |table| {
            if (self.discarding) {
                table.deinit(self.allocator);
                self.allocator.destroy(table);
            } else self.destroyTable(table);
        }
        for (self.proto_allocations.items[self.borrowed_proto_count..]) |proto| {
            proto.deinit();
            self.allocator.destroy(proto);
        }
        for (self.source_allocations.items) |source| self.allocator.free(source);
        for (self.string_allocations.items) |allocation| self.allocator.free(allocation.bytes);
        self.api_roots.deinit(self.allocator);
        self.source_allocations.deinit(self.allocator);
        self.proto_allocations.deinit(self.allocator);
        self.thread_allocations.deinit(self.allocator);
        self.upvalue_allocations.deinit(self.allocator);
        self.closure_allocations.deinit(self.allocator);
        self.userdata_allocations.deinit(self.allocator);
        self.table_allocations.deinit(self.allocator);
        self.string_allocations.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn execute(self: *State, proto: *proto_mod.Proto) !void {
        try value_mod.prepareProtoTree(proto);
        try self.executeClosure(try self.newRootClosure(proto), .{ .host_frame = true });
    }

    // Heap-allocated so coroutine.running() can expose a stable identity; unexposed ones are released after the call.
    fn newHostThread(self: *State, closure: *Closure) !*Thread {
        const thread = try self.allocator.create(Thread);
        errdefer self.allocator.destroy(thread);
        thread.* = try Thread.initRoot(self.allocator, closure, self.stackValueLimit());
        errdefer thread.deinit(self.allocator);
        try self.registerAllocation("thread_allocations", thread);
        self.noteAllocation(@sizeOf(Thread));
        return thread;
    }

    fn retireHostThread(self: *State, thread: *Thread) void {
        gc_mod.syncThreadStorage(State, self, thread);
        self.closeUpvalues(thread, 0);
        if (!thread.exposed) {
            const index = self.object_allocation_index.get(@intFromPtr(thread)).?;
            gc_mod.forgetThread(State, self, thread);
            gc_mod.removeRegistryItem(State, self, "thread_allocations", index);
            self.noteAllocationFreed(@sizeOf(Thread) + thread.gc.storage_bytes);
            self.destroyThread(thread);
            return;
        }
        // Drop storage borrowed from the host stack, keeping the observable thread and its hook.
        const retained = Thread{
            .marked = thread.marked,
            .gc = thread.gc,
            .exposed = true,
            .is_main = true,
            .started = true,
            .status = .dead,
            .hook = thread.hook,
            .hook_call = thread.hook_call,
            .hook_line = thread.hook_line,
            .hook_return = thread.hook_return,
            .hook_count = thread.hook_count,
            .hook_count_remaining = thread.hook_count_remaining,
            .error_traceback = thread.error_traceback,
        };
        thread.deinit(self.allocator);
        thread.* = retained;
        gc_mod.syncThreadStorage(State, self, thread);
    }

    pub fn callLoadedClosure(self: *State, closure: *Closure, args: []const Value) ![]Value {
        return self.callLoadedClosureHandled(closure, args, .{});
    }

    /// Like `callLoadedClosure`; `handler` runs at the error point before frames unwind.
    pub fn callLoadedClosureHandled(self: *State, closure: *Closure, args: []const Value, handler: HostErrorHandler) ![]Value {
        const thread = self.newHostThread(closure) catch |err| switch (err) {
            error.StackOverflow => return self.fail("stack overflow"),
            else => return err,
        };
        defer self.retireHostThread(thread);
        try self.setRootThreadArgs(thread, args);
        thread.frames.items[0].return_count = bytecode.multret_count;
        installHostErrorHandler(thread, handler);
        const previous_thread = self.current_thread;
        self.current_thread = thread;
        defer self.current_thread = previous_thread;
        self.runThreadUntil(thread, 0) catch |err| {
            try self.unwindHostThread(thread, err, handler);
            return err;
        };
        thread.status = .dead;
        return self.copyStackSlice(thread, thread.last_result_base, thread.last_result_count);
    }

    pub fn protectedCallLoadedClosure(self: *State, closure: *Closure, args: []const Value) !ProtectedCallResult {
        return self.protectedCallLoadedClosureHandled(closure, args, .{});
    }

    /// Like `protectedCallLoadedClosure`; `handler` runs at the error point before frames unwind.
    pub fn protectedCallLoadedClosureHandled(self: *State, closure: *Closure, args: []const Value, handler: HostErrorHandler) !ProtectedCallResult {
        const thread = self.newHostThread(closure) catch |err| switch (err) {
            error.StackOverflow => return .{ .failure = .{ .string = try self.intern("stack overflow") } },
            else => return err,
        };
        defer self.retireHostThread(thread);
        try self.setRootThreadArgs(thread, args);
        thread.frames.items[0].return_count = bytecode.multret_count;
        installHostErrorHandler(thread, handler);
        const previous_thread = self.current_thread;
        self.current_thread = thread;
        defer self.current_thread = previous_thread;

        self.last_error = null;
        self.runThreadUntil(thread, 0) catch |err| switch (err) {
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => {
                self.noteCaughtError(err);
                if (self.options.debug_errors) self.appendUnhandledErrorDebugDump(thread, err) catch {};
                self.applyHostErrorHandler(thread, handler) catch |handler_err| {
                    thread.status = .dead;
                    return handler_err;
                };
                var failure = self.currentErrorValue();
                self.closeFramesTo(thread, 0, failure) catch |close_err| switch (close_err) {
                    error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => failure = self.currentErrorValue(),
                    else => return close_err,
                };
                thread.status = .dead;
                return .{ .failure = failure };
            },
            error.LuaExit => {
                try self.finishExitUnwind(thread);
                thread.status = .dead;
                return err;
            },
            else => {
                thread.status = .dead;
                return err;
            },
        };
        thread.status = .dead;
        return .{ .success = try self.copyStackSlice(thread, thread.last_result_base, thread.last_result_count) };
    }

    pub fn callFunction(self: *State, function: Value, args: []const Value) ![]Value {
        return self.callFunctionHandled(function, args, .{});
    }

    /// Like `callFunction`; `handler` runs at the error point before frames unwind.
    pub fn callFunctionHandled(self: *State, function: Value, args: []const Value, handler: HostErrorHandler) ![]Value {
        if (function == .closure) return self.callLoadedClosureHandled(function.closure, args, handler);
        // A native callee still needs a frame for arguments, errors, and reentrant Lua calls.
        var proto = proto_mod.Proto.init(self.allocator);
        defer proto.deinit();
        proto.source_name = "=[C]";
        var closure = Closure{ .proto = &proto, .upvalues = &.{} };
        const thread = self.newHostThread(&closure) catch |err| switch (err) {
            error.StackOverflow => return self.fail("stack overflow"),
            else => return err,
        };
        defer self.retireHostThread(thread);
        installHostErrorHandler(thread, handler);
        const previous_thread = self.current_thread;
        self.current_thread = thread;
        defer self.current_thread = previous_thread;
        self.last_error = null;
        return self.callCollect(thread, function, args) catch |err| {
            if (err == error.Interrupted and self.execution_depth == 0) self.consumeInterrupt();
            try self.unwindHostThread(thread, err, handler);
            return err;
        };
    }

    pub fn protectedCallFunction(self: *State, function: Value, args: []const Value) !ProtectedCallResult {
        return self.protectedCallFunctionHandled(function, args, .{});
    }

    /// Like `protectedCallFunction`; `handler` runs at the error point before frames unwind.
    pub fn protectedCallFunctionHandled(self: *State, function: Value, args: []const Value, handler: HostErrorHandler) !ProtectedCallResult {
        if (function == .closure) return self.protectedCallLoadedClosureHandled(function.closure, args, handler);
        const values = self.callFunctionHandled(function, args, handler) catch |err| switch (err) {
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => return .{ .failure = self.currentErrorValue() },
            else => return err,
        };
        return .{ .success = values };
    }

    pub fn executeSourceChunk(self: *State, source: []const u8) !void {
        const loaded = try self.loadSourceAsClosure(source);
        try self.executeClosure(loaded.closure, .{});
    }

    pub fn executeSourceChunkNamed(self: *State, source: []const u8, source_name: []const u8) !void {
        return self.executeSourceChunkNamedHandled(source, source_name, .{});
    }

    /// Like `executeSourceChunkNamed`; `handler` runs at a runtime error point before frames unwind.
    pub fn executeSourceChunkNamedHandled(self: *State, source: []const u8, source_name: []const u8, handler: HostErrorHandler) !void {
        const loaded = try self.loadSourceAsClosureNamed(source, source_name);
        try self.executeClosure(loaded.closure, handler);
    }

    fn executeClosure(self: *State, closure: *Closure, handler: HostErrorHandler) !void {
        const thread = self.newHostThread(closure) catch |err| switch (err) {
            error.StackOverflow => return self.fail("stack overflow"),
            else => return err,
        };
        defer self.retireHostThread(thread);
        installHostErrorHandler(thread, handler);
        const previous_thread = self.current_thread;
        self.current_thread = thread;
        defer self.current_thread = previous_thread;
        self.runThreadUntil(thread, 0) catch |err| {
            try self.unwindHostThread(thread, err, handler);
            return err;
        };
        thread.status = .dead;
    }

    fn installHostErrorHandler(thread: *Thread, handler: HostErrorHandler) void {
        thread.error_handler = handler.message_handler;
        thread.host_frame = handler.host_frame;
    }

    fn unwindHostThread(self: *State, thread: *Thread, err: anyerror, handler: HostErrorHandler) !void {
        defer thread.status = .dead;
        if (err == error.LuaExit) return self.finishExitUnwind(thread);
        if (err == error.Interrupted) return;
        self.noteCaughtError(err);
        if (self.options.debug_errors and isRuntimeError(err)) self.appendUnhandledErrorDebugDump(thread, err) catch {};
        if (isRuntimeError(err)) try self.applyHostErrorHandler(thread, handler);
        try self.closeFramesTo(thread, 0, self.currentErrorValue());
    }

    fn applyHostErrorHandler(self: *State, thread: *Thread, handler: HostErrorHandler) !void {
        if (handler.traceback) |out| {
            if (out.*) |previous| self.allocator.free(previous);
            out.* = null;
            out.* = try debug_mod.formatTraceback(State, self, thread, handler.host_frame);
        }
        if (thread.frames.items.len != 0) try self.applyMessageHandler(thread);
    }

    /// Records stack overflow and memory errors caught from Lua execution; memory
    /// errors skip message handlers as in Lua.
    pub fn noteCaughtError(self: *State, err: anyerror) void {
        switch (err) {
            error.StackOverflow => if (self.last_error == null) {
                self.last_error = .{ .diagnostic = "stack overflow" };
                self.error_handled = false;
            },
            error.OutOfMemory => {
                if (self.last_error == null) self.last_error = .{ .diagnostic = "not enough memory" };
                self.error_handled = true;
            },
            else => {},
        }
    }

    /// Runs the message handler on top of the failing frames, like `luaG_errormsg`.
    /// Handler errors retry until Lua's C-call limit yields "error in error handling".
    pub fn applyMessageHandler(self: *State, thread: *Thread) !void {
        if (self.error_handled) return;
        self.error_handled = true;
        const handler = thread.error_handler;
        if (handler == .nil) return;
        var error_value = self.currentErrorValue();
        const mark_count = thread.native_mark_count;
        defer thread.native_mark_count = mark_count;
        const start_frames = thread.frames.items.len;
        var c_calls = self.execution_depth + 2;
        var overflowed = false;
        var native_calls: usize = 0;
        while (true) {
            c_calls = @max(c_calls + 1, self.execution_depth + 3 + native_calls + debug_mod.indirectFrameCount(thread, start_frames));
            if (c_calls >= lua_max_c_calls and !overflowed) {
                overflowed = true;
                error_value = try self.cStackOverflowValue(thread);
                native_calls += 1;
                continue;
            }
            if (c_calls >= lua_max_c_calls / 10 * 11) {
                error_value = .{ .string = try self.intern("error in error handling") };
                break;
            }
            if (handler != .closure) native_calls += 1;
            const frame_count = thread.frames.items.len;
            if (try self.callMessageHandler(thread, handler, error_value)) |result| {
                error_value = result;
                break;
            }
            if (handler != .closure and thread.frames.items.len > frame_count) pushNativeMark(thread, frame_count, handler);
            error_value = self.currentErrorValue();
            if (self.error_handled) break;
        }
        self.last_error = .{ .lua_value = error_value };
        self.error_handled = true;
    }

    fn callMessageHandler(self: *State, thread: *Thread, handler: Value, error_value: Value) !?Value {
        const context = self.protectedCallContext(thread);
        thread.ensureStack(self.allocator, context.absolute_base + 2, self.stackValueLimit() + stack_error_values) catch |err| switch (err) {
            error.StackOverflow => return self.errorInErrorHandling(),
            else => return err,
        };
        thread.stack.items[context.absolute_base] = handler;
        thread.stack.items[context.absolute_base + 1] = error_value;
        thread.native_call_depth += 1;
        defer thread.native_call_depth -= 1;
        const previous_native_call = thread.native_call;
        defer thread.native_call = previous_native_call;
        if (!debug_mod.errorRaisedByLuaCode(thread)) thread.native_call = runtimeNativeCall(thread);
        const name = debug_mod.messageHandlerCallName(thread);
        thread.next_call_name = if (name) |known| known.name else null;
        thread.next_call_namewhat = if (name) |known| known.namewhat else null;
        self.invokeValue(thread, .{ .base = context.relative_base, .arg_count = 1, .return_count = bytecode.multret_count }, 0) catch |err| return self.messageHandlerFailure(err);
        self.runThreadUntil(thread, context.frame_count) catch |err| return self.messageHandlerFailure(err);
        const result = if (thread.last_result_count == 0) Value.nil else thread.stack.items[thread.last_result_base];
        thread.stack.items.len = context.stack_len;
        thread.last_result_base = context.last_result_base;
        thread.last_result_count = context.last_result_count;
        return result;
    }

    fn cStackOverflowValue(self: *State, thread: *Thread) !Value {
        const message = "C stack overflow";
        if (!debug_mod.errorRaisedByLuaCode(thread)) return .{ .string = try self.intern(message) };
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const site = self.instructionErrorSite(thread) orelse return .{ .string = try self.intern(message) };
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        try appendFmt(self.allocator, &out, "{s}:{d}: {s}", .{ runtimeSourceName(frame.proto.source_name), site.line, message });
        return .{ .string = try self.intern(out.items) };
    }

    /// Records a native function without a calling instruction for tracebacks.
    pub fn pushNativeMark(thread: *Thread, frame_count: usize, callee: Value) void {
        if (thread.native_mark_count == thread.native_marks.len) return;
        thread.native_marks[thread.native_mark_count] = .{ .frame_count = @intCast(frame_count), .callee = callee };
        thread.native_mark_count += 1;
    }

    fn messageHandlerFailure(self: *State, err: anyerror) !?Value {
        switch (err) {
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode, error.OutOfMemory => {
                self.noteCaughtError(err);
                return null;
            },
            else => return err,
        }
    }

    fn checkCStack(self: *State, thread: *Thread) !void {
        if (self.execution_depth >= lua_max_c_calls / 10 * 11) {
            _ = try self.errorInErrorHandling();
            return error.RuntimeError;
        }
        if (self.execution_depth != lua_max_c_calls) return;
        const frame_count = thread.frames.items.len;
        if (frame_count > 1) thread.frames.items.len = frame_count - 1;
        const value = self.cStackOverflowValue(thread);
        thread.frames.items.len = frame_count;
        return self.failValue(try value);
    }

    fn errorInErrorHandling(self: *State) !?Value {
        self.last_error = .{ .lua_value = .{ .string = try self.intern("error in error handling") } };
        self.error_handled = true;
        return null;
    }

    pub fn runThreadUntil(self: *State, thread: *Thread, target_frame_count: usize) anyerror!void {
        self.runThreadLoop(thread, target_frame_count) catch |err| {
            if (err == error.Interrupted and self.execution_depth == 0) self.consumeInterrupt();
            return err;
        };
    }

    fn runThreadLoop(self: *State, thread: *Thread, target_frame_count: usize) anyerror!void {
        defer gc_mod.syncThreadStorage(State, self, thread);
        gc_mod.rememberObject(State, self, .{ .thread = thread });
        self.execution_depth += 1;
        defer self.execution_depth -= 1;
        if (self.execution_depth >= lua_max_c_calls) try self.checkCStack(thread);
        try rollback_mod.threadWritable(thread);
        while (thread.frames.items.len > target_frame_count) {
            if (thread.pending_unwind_error != null or thread.pending_yield_hook_return or hasPendingContinuations(thread)) {
                if (thread.pending_unwind_error != null and thread.frames.items.len == thread.pending_unwind_resume_frame_count) {
                    const error_value = thread.pending_unwind_error.?;
                    const target = thread.pending_unwind_target_frame_count;
                    thread.pending_unwind_error = null;
                    try self.closeFramesTo(thread, target, error_value);
                    return self.rethrowValue(error_value);
                }
                if (thread.frames.items.len <= thread.continuation_frame_count) {
                    if (try self.completeReadyPairsContinuation(thread)) continue;
                    if (try self.completeReadyCallOneContinuation(thread)) continue;
                    if (try self.completeReadyProtectedContinuation(thread)) continue;
                    if (try self.completeReadyTailCallContinuation(thread)) continue;
                    if (try self.completeReadyGenericForContinuation(thread)) continue;
                }
                if (thread.pending_yield_hook_return) {
                    thread.pending_yield_hook_return = false;
                    try self.callHook(thread, "return");
                    continue;
                }
            }
            var frame = &thread.frames.items[thread.frames.items.len - 1];
            const proto = frame.proto;
            if (frame.pc >= proto.instructions.items.len) {
                try self.returnFromFrame(thread, 0, 0);
                continue;
            }
            const pc = frame.pc;
            const instruction = proto.instructions.items[pc];
            if (proto.fast_loop_entry and plainFastLoopCanStart(instruction) and self.runPlainFastLoop(thread, target_frame_count)) continue;
            frame.pc += 1;
            try self.checkExecutionLimits(thread);
            if (self.options.trace_vm) try self.traceInstruction(frame.*, pc, instruction);
            if (thread.hook != .nil) {
                try self.callLineHook(thread);
                try self.callCountHook(thread);
            }

            frame = &thread.frames.items[thread.frames.items.len - 1];
            const base = frame.base;
            const stack = thread.stack.items;

            switch (instruction) {
                .load_nil => |dest| stack[base + dest] = .nil,
                .load_bool => |op| stack[base + op.dest] = .{ .boolean = op.value },
                .load_const => |op| stack[base + op.dest] = try self.protoConstant(frame.closure, proto, op.constant),
                .move => |op| stack[base + op.dest] = stack[base + op.source],
                .get_global => |op| stack[base + op.register] = self.getGlobalValue(constantString(proto, op.name)),
                .set_global => |op| try self.setGlobal(constantString(proto, op.name), stack[base + op.register]),
                .declare_global => |op| try self.declareGlobal(thread, constantString(proto, op.name), op.table, op.value),
                .add => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawNumericBinaryOpFast(lhs, rhs, .add)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .add);
                    }
                },
                .sub => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawNumericBinaryOpFast(lhs, rhs, .sub)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .sub);
                    }
                },
                .mul => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawNumericBinaryOpFast(lhs, rhs, .mul)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .mul);
                    }
                },
                .div => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawNumericBinaryOpFast(lhs, rhs, .div)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .div);
                    }
                },
                .idiv => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawNumericBinaryOpFast(lhs, rhs, .idiv)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .idiv);
                    }
                },
                .mod => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawNumericBinaryOpFast(lhs, rhs, .mod)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .mod);
                    }
                },
                .pow => |op| try self.binaryOpToRegister(thread, op, .pow),
                .band => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawIntegerBitwiseOpFast(lhs, rhs, .band)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .band);
                    }
                },
                .bor => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawIntegerBitwiseOpFast(lhs, rhs, .bor)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .bor);
                    }
                },
                .bxor => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawIntegerBitwiseOpFast(lhs, rhs, .bxor)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .bxor);
                    }
                },
                .shl => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawIntegerBitwiseOpFast(lhs, rhs, .shl)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .shl);
                    }
                },
                .shr => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawIntegerBitwiseOpFast(lhs, rhs, .shr)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.binaryOpToRegister(thread, op, .shr);
                    }
                },
                .unm => |op| try self.unaryOpToRegister(thread, op, .unm),
                .bnot => |op| try self.unaryOpToRegister(thread, op, .bnot),
                .concat => |op| try self.binaryOpToRegister(thread, op, .concat),
                .concat_range => |op| try self.concatRangeToRegister(thread, op),
                .eq => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (!equalityHasMetamethod(lhs, rhs)) {
                        stack[base + op.dest] = .{ .boolean = valuesEqual(lhs, rhs) };
                    } else {
                        try self.equalValuesToRegister(thread, op);
                    }
                },
                .lt => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawCompare(lhs, rhs, .lt)) |result| {
                        stack[base + op.dest] = .{ .boolean = result };
                    } else {
                        try self.compareValuesToRegister(thread, op, .lt);
                    }
                },
                .le => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawCompare(lhs, rhs, .le)) |result| {
                        stack[base + op.dest] = .{ .boolean = result };
                    } else {
                        try self.compareValuesToRegister(thread, op, .le);
                    }
                },
                .not => |op| {
                    const result = !truthy(stack[base + op.source]);
                    stack[base + op.dest] = .{ .boolean = result };
                },
                .len => |op| try self.lengthToRegister(thread, op),
                .new_table => |op| stack[base + op.dest] = try self.newTableWithHints(op.array_hint, op.hash_hint),
                .set_list => |op| try self.setList(thread, op),
                .get_table => |op| {
                    const table_value = stack[base + op.table];
                    const key_value = stack[base + op.key];
                    if (frame.named_vararg_readonly and op.table == proto.param_count) {
                        stack[base + op.dest] = namedVarargRead(frame.varargs, key_value);
                    } else if (fastTableRawGet(table_value, key_value)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.getTableToRegister(thread, op.dest, table_value, key_value);
                    }
                },
                .set_table => |op| {
                    const table_value = stack[base + op.table];
                    const key_value = stack[base + op.key];
                    const value = stack[base + op.value];
                    if (!try self.fastTableArraySet(table_value, key_value, value)) {
                        if (key_value != .string or !try self.fastTableKnownKeySet(table_value, key_value, value)) {
                            try self.setTableFromThreadContinuable(thread, table_value, key_value, value);
                        }
                    }
                },
                .set_array => |op| {
                    const table_value = stack[base + op.table];
                    const value = stack[base + op.value];
                    if (table_value == .table and op.index != 0) {
                        try self.setTableArrayRawIndex(table_value.table, op.index, value);
                    } else {
                        try self.setTableFromThreadContinuable(thread, table_value, .{ .integer = @intCast(op.index) }, value);
                    }
                },
                .get_field => |op| {
                    const table_value = stack[base + op.table];
                    const key = Value{ .string = constantString(proto, op.name) };
                    if (frame.named_vararg_readonly and op.table == proto.param_count) {
                        stack[base + op.dest] = namedVarargRead(frame.varargs, key);
                    } else if (fastTableRawGet(table_value, key)) |value| {
                        stack[base + op.dest] = value;
                    } else {
                        try self.getTableToRegister(thread, op.dest, table_value, key);
                    }
                },
                .set_field => |op| {
                    const table_value = stack[base + op.table];
                    const key = Value{ .string = constantString(proto, op.name) };
                    const value = stack[base + op.value];
                    if (!try self.fastTableKnownKeySet(table_value, key, value)) {
                        try self.setTableFromThreadContinuable(thread, table_value, key, value);
                    }
                },
                .jmp => |offset| try self.jumpThreadMaybeFast(thread, offset, true),
                .compare_branch => |op| {
                    const lhs = stack[base + op.left];
                    const rhs = stack[base + op.right];
                    if (rawCompareBranchResult(lhs, rhs, op.op)) |result| {
                        if (result == op.jump_if_truthy) try self.jumpThreadMaybeFast(thread, op.offset, true);
                    } else {
                        try self.compareBranch(thread, op);
                    }
                },
                .test_op => |op| if (truthy(stack[base + op.register]) == op.jump_if_truthy) {
                    try self.jumpThreadMaybeFast(thread, op.offset, true);
                },
                .test_set => |op| {
                    const value = stack[base + op.source];
                    stack[base + op.dest] = value;
                    if (truthy(value) == op.jump_if_truthy) {
                        try self.jumpThreadMaybeFast(thread, op.offset, true);
                    }
                },
                .call => |op| try self.callValue(thread, op),
                .tail_call => |op| try self.tailCallValue(thread, op),
                .ret => |op| try self.returnFromFrame(thread, op.first, op.count),
                .vararg => |op| try self.loadVarargs(thread, op),
                .for_prep => |op| try self.forPrep(thread, op),
                .for_loop => |op| try self.forLoop(thread, op),
                .tfor_prep => |op| if (!(try self.advanceGenericFor(thread, op, true))) try self.jumpThread(thread, op.offset, false),
                .tfor_call => |op| _ = try self.advanceGenericFor(thread, op, false),
                .tfor_loop => |op| try self.jumpThread(thread, op.offset, false),
                .closure => |op| stack[base + op.dest] = try self.newClosure(thread, proto.children.items[op.proto]),
                .get_upvalue => |op| stack[base + op.register] = self.readUpvalue(thread, op.upvalue),
                .set_upvalue => |op| try self.writeUpvalue(thread, op.upvalue, stack[base + op.register]),
                .close => |register| if (thread.open_upvalues != null) self.closeUpvalues(thread, base + register),
                .check_close => |register| try self.checkToBeClosedRegister(thread, register),
                .close_tbc => |register| try self.closeToBeClosedRegister(thread, register, null),
            }

            if (!instructionPreservesLastResult(instruction)) {
                thread.last_result_count = 0;
                thread.last_transfer_count = 0;
            }

            if (self.gc_running and (self.shouldRunAutoGc() or self.stressPending())) try gc_mod.autoStep(State, self, thread);
        }
    }

    fn runPlainFastLoop(self: *State, thread: *Thread, target_frame_count: usize) bool {
        if (thread.frames.items.len <= target_frame_count) return false;
        if (self.instructionBudgetActive() or self.options.trace_vm) return false;
        if (self.fastLoopInterrupted()) return false;
        if (self.stressPending()) return false;
        if (thread.hook != .nil and (thread.hook_line or thread.hook_count != 0 or thread.hook_running)) return false;
        if (self.gc_running and self.shouldRunAutoGc()) return false;

        const stack_limit = @min(thread.stack.items.len, self.stackValueLimit());
        const frame_limit = @min(thread.frames.capacity, self.callFrameLimit());
        const return_floor: usize = if (thread.pending_unwind_error != null or thread.pending_yield_hook_return or thread.hook_return)
            std.math.maxInt(usize)
        else if (hasPendingContinuations(thread))
            @max(target_frame_count, thread.continuation_frame_count)
        else
            target_frame_count;

        var frame_index = thread.frames.items.len - 1;
        var frame = &thread.frames.items[frame_index];
        var proto = frame.proto;
        var pc = frame.pc;
        var base = frame.base;
        var count_bias: u64 = 0 -% pc;
        defer self.instruction_count = self.instruction_count +| (pc +% count_bias);
        var segment_start: u64 = 0;
        frames: while (true) {
            if (!proto.fast_loop_entry) return segment_start != 0;
            const instructions = proto.instructions.items;
            if (pc >= instructions.len) return segment_start != 0;
            const stack = thread.stack.items[base..];

            // Per-opcode dispatch on the tag only; handlers decode operands so the union is never copied.
            fast_loop: switch (std.meta.activeTag(instructions[pc])) {
                .load_nil => {
                    const dest = instructions[pc].load_nil;
                    stack[dest] = .nil;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .load_bool => {
                    const op = instructions[pc].load_bool;
                    stack[op.dest] = .{ .boolean = op.value };
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .load_const => {
                    const op = instructions[pc].load_const;
                    const decoded = &proto.constant_values[op.constant];
                    if (decoded.* != .string) {
                        stack[op.dest] = decoded.*;
                    } else {
                        const constants = frame.closure.constants orelse break :fast_loop;
                        const cached = &constants[op.constant];
                        if (cached.* == null) break :fast_loop;
                        stack[op.dest] = cached.*.?;
                    }
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .move => {
                    const op = instructions[pc].move;
                    stack[op.dest] = stack[op.source];
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .get_upvalue => {
                    const op = instructions[pc].get_upvalue;
                    const upvalue = frame.closure.upvalues[op.upvalue];
                    stack[op.register] = if (upvalue.is_open) upvalue.owner.stack.items[upvalue.stack_index] else upvalue.closed;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .set_upvalue => {
                    const op = instructions[pc].set_upvalue;
                    const upvalue = frame.closure.upvalues[op.upvalue];
                    if (upvalue.is_open) {
                        if (upvalue.owner.rollback) |record| if (!record.header.detached) break :fast_loop;
                        rollback_mod.touch(upvalue);
                        upvalue.owner.stack.items[upvalue.stack_index] = stack[op.register];
                        if (upvalue.owner != thread) gc_mod.rememberObject(State, self, .{ .thread = upvalue.owner });
                    } else {
                        rollback_mod.touch(upvalue);
                        upvalue.closed = stack[op.register];
                        self.writeBarrier(upvalue, upvalue.closed);
                    }
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .add => {
                    const op = instructions[pc].add;
                    const value = rawNumericBinaryOpFast(stack[op.left], stack[op.right], .add) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .sub => {
                    const op = instructions[pc].sub;
                    const value = rawNumericBinaryOpFast(stack[op.left], stack[op.right], .sub) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .mul => {
                    const op = instructions[pc].mul;
                    const value = rawNumericBinaryOpFast(stack[op.left], stack[op.right], .mul) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .div => {
                    const op = instructions[pc].div;
                    const value = rawNumericBinaryOpFast(stack[op.left], stack[op.right], .div) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .idiv => {
                    const op = instructions[pc].idiv;
                    const value = rawNumericBinaryOpFast(stack[op.left], stack[op.right], .idiv) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .mod => {
                    const op = instructions[pc].mod;
                    const value = rawNumericBinaryOpFast(stack[op.left], stack[op.right], .mod) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .band => {
                    const op = instructions[pc].band;
                    const value = rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .band) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .bor => {
                    const op = instructions[pc].bor;
                    const value = rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .bor) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .bxor => {
                    const op = instructions[pc].bxor;
                    const value = rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .bxor) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .shl => {
                    const op = instructions[pc].shl;
                    const value = rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .shl) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .shr => {
                    const op = instructions[pc].shr;
                    const value = rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .shr) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .eq => {
                    const op = instructions[pc].eq;
                    const lhs = stack[op.left];
                    const rhs = stack[op.right];
                    if (equalityHasMetamethod(lhs, rhs) and !valuesEqual(lhs, rhs)) break :fast_loop;
                    stack[op.dest] = .{ .boolean = valuesEqual(lhs, rhs) };
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .lt => {
                    const op = instructions[pc].lt;
                    const result = rawCompare(stack[op.left], stack[op.right], .lt) orelse break :fast_loop;
                    stack[op.dest] = .{ .boolean = result };
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .le => {
                    const op = instructions[pc].le;
                    const result = rawCompare(stack[op.left], stack[op.right], .le) orelse break :fast_loop;
                    stack[op.dest] = .{ .boolean = result };
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .not => {
                    const op = instructions[pc].not;
                    const result = !truthy(stack[op.source]);
                    stack[op.dest] = .{ .boolean = result };
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .unm => {
                    const op = instructions[pc].unm;
                    stack[op.dest] = switch (stack[op.source]) {
                        .integer => |value| .{ .integer = -%value },
                        .number => |value| .{ .number = -value },
                        else => break :fast_loop,
                    };
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .bnot => {
                    const op = instructions[pc].bnot;
                    const value = stack[op.source];
                    if (value != .integer) break :fast_loop;
                    stack[op.dest] = .{ .integer = ~value.integer };
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .len => {
                    const op = instructions[pc].len;
                    const value = fastLengthNoMetamethod(stack[op.source]) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .get_table => {
                    const op = instructions[pc].get_table;
                    const value = if (frame.named_vararg_readonly and op.table == proto.param_count)
                        namedVarargRead(frame.varargs, stack[op.key])
                    else
                        fastTableRawGet(stack[op.table], stack[op.key]) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .get_field => {
                    const op = instructions[pc].get_field;
                    const key = Value{ .string = constantString(proto, op.name) };
                    const value = if (frame.named_vararg_readonly and op.table == proto.param_count)
                        namedVarargRead(frame.varargs, key)
                    else
                        fastTableRawGet(stack[op.table], key) orelse break :fast_loop;
                    stack[op.dest] = value;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .set_table => {
                    const op = instructions[pc].set_table;
                    if (!self.fastTableArraySetExistingNoAlloc(stack[op.table], stack[op.key], stack[op.value]) and
                        !self.fastTableKnownKeySetExistingNoAlloc(stack[op.table], stack[op.key], stack[op.value])) break :fast_loop;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .set_array => {
                    const op = instructions[pc].set_array;
                    const table_value = stack[op.table];
                    if (table_value != .table or op.index == 0) break :fast_loop;
                    const table = table_value.table;
                    if (table.rollback) |record| if (!record.header.detached) break :fast_loop;
                    const index: usize = op.index;
                    const value = stack[op.value];
                    if (index <= table.array.items.len) {
                        table.array.items[index - 1] = value;
                    } else if (value != .nil) {
                        if (index > table.array.capacity) break :fast_loop;
                        const old_len = table.array.items.len;
                        table.array.items.len = index;
                        @memset(table.array.items[old_len..], .nil);
                        table.array.items[index - 1] = value;
                    }
                    self.writeTableBarrier(table, .{ .integer = @intCast(index) }, value);
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .set_field => {
                    const op = instructions[pc].set_field;
                    const key = Value{ .string = constantString(proto, op.name) };
                    if (!self.fastTableKnownKeySetExistingNoAlloc(stack[op.table], key, stack[op.value])) break :fast_loop;
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .compare_branch => {
                    const op = instructions[pc].compare_branch;
                    const result = rawCompareBranchResult(stack[op.left], stack[op.right], op.op) orelse break :fast_loop;
                    pc += 1;
                    if (result == op.jump_if_truthy) {
                        const source_pc = pc;
                        pc = jumpTarget(source_pc, op.offset);
                        count_bias +%= source_pc -% pc;
                        if (pc < source_pc) {
                            frame.last_hook_line = null;
                            if (self.fastLoopInterrupted()) break :fast_loop;
                        }
                    }
                    if (pc >= instructions.len) break :fast_loop;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .jmp => {
                    const offset = instructions[pc].jmp;
                    pc += 1;
                    const source_pc = pc;
                    pc = jumpTarget(source_pc, offset);
                    count_bias +%= source_pc -% pc;
                    if (pc < source_pc) {
                        frame.last_hook_line = null;
                        if (self.fastLoopInterrupted()) break :fast_loop;
                    }
                    if (pc >= instructions.len) break :fast_loop;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .test_op => {
                    const op = instructions[pc].test_op;
                    pc += 1;
                    if (truthy(stack[op.register]) == op.jump_if_truthy) {
                        const source_pc = pc;
                        pc = jumpTarget(source_pc, op.offset);
                        count_bias +%= source_pc -% pc;
                        if (pc < source_pc) {
                            frame.last_hook_line = null;
                            if (self.fastLoopInterrupted()) break :fast_loop;
                        }
                    }
                    if (pc >= instructions.len) break :fast_loop;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .test_set => {
                    const op = instructions[pc].test_set;
                    const value = stack[op.source];
                    stack[op.dest] = value;
                    pc += 1;
                    if (truthy(value) == op.jump_if_truthy) {
                        const source_pc = pc;
                        pc = jumpTarget(source_pc, op.offset);
                        count_bias +%= source_pc -% pc;
                        if (pc < source_pc) {
                            frame.last_hook_line = null;
                            if (self.fastLoopInterrupted()) break :fast_loop;
                        }
                    }
                    if (pc >= instructions.len) break :fast_loop;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .for_loop => {
                    const op = instructions[pc].for_loop;
                    const absolute_base: usize = op.base;
                    const current = stack[absolute_base];
                    const limit = stack[absolute_base + 1];
                    const step = stack[absolute_base + 2];
                    const continues = if (current == .integer and limit == .integer and step == .integer) blk: {
                        const next = current.integer +% step.integer;
                        stack[absolute_base] = .{ .integer = next };
                        const wrapped = (step.integer > 0 and next < current.integer) or (step.integer < 0 and next > current.integer);
                        break :blk !wrapped and forLoopContinuesInteger(next, limit.integer, step.integer);
                    } else if (current == .number and limit == .number and step == .number) blk: {
                        const next = current.number + step.number;
                        stack[absolute_base] = .{ .number = next };
                        break :blk forLoopContinuesNumber(next, limit.number, step.number);
                    } else break :fast_loop;
                    pc += 1;
                    if (continues) {
                        const source_pc = pc;
                        pc = jumpTarget(source_pc, op.offset);
                        count_bias +%= source_pc -% pc;
                        if (pc < source_pc) {
                            frame.last_hook_line = null;
                            if (self.fastLoopInterrupted()) break :fast_loop;
                        }
                    }
                    if (pc >= instructions.len) break :fast_loop;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                .call => {
                    var op = instructions[pc].call;
                    if (thread.hook_call) break :fast_loop;
                    if (op.arg_count == bytecode.multret_arg_count) {
                        // Only valid while a preceding call/vararg still owns the last-result state.
                        if (pc +% count_bias != segment_start) break :fast_loop;
                        const expected_base = base + op.base + 1;
                        if (thread.last_result_base < expected_base) break :fast_loop;
                        const result_end = thread.last_result_base + thread.last_result_count;
                        op.arg_count = @intCast(result_end -| expected_base);
                    }
                    const callee = stack[op.base];
                    if (callee == .native and !thread.hook_return) {
                        if (op.arg_count == 0 or @as(usize, op.base) + 1 >= stack.len) break :fast_loop;
                        const result = stdlib.math.fastUnaryResult(callee.native, stack[op.base + 1]) orelse break :fast_loop;
                        const return_count: usize = if (op.return_count == bytecode.multret_count) 1 else op.return_count;
                        const absolute_base = base + op.base;
                        const stored_end = absolute_base + @max(return_count, 1);
                        if (stored_end > stack_limit) break :fast_loop;
                        stack[op.base] = result;
                        if (return_count > 1) @memset(thread.stack.items[absolute_base + 1 .. stored_end], .nil);
                        thread.last_result_base = absolute_base;
                        thread.last_result_count = return_count;
                        thread.last_transfer_base = absolute_base;
                        thread.last_transfer_count = 1;
                        thread.next_call_name = null;
                        thread.next_call_namewhat = null;
                        pc += 1;
                        frame.pc = pc;
                        segment_start = pc +% count_bias;
                        continue :frames;
                    }
                    if (callee != .closure) break :fast_loop;
                    const closure = callee.closure;
                    const callee_proto = closure.proto;
                    // Growth, varargs, and hooks need the general path, which can allocate or reenter Lua.
                    if (!callee_proto.fast_loop_call) break :fast_loop;
                    const callee_index = frame_index + 1;
                    if (callee_index >= frame_limit) break :fast_loop;
                    const function_slot = base + op.base;
                    const callee_base = function_slot + 1;
                    const register_count = @max(callee_proto.max_registers, 1);
                    const stack_end = callee_base + register_count;
                    if (stack_end > stack_limit) break :fast_loop;

                    const executed_count = pc +% count_bias -% segment_start;
                    const copied = @min(op.arg_count, callee_proto.param_count);
                    @memset(thread.stack.items[callee_base + copied .. stack_end], .nil);
                    frame.pc = pc + 1;
                    frame = &@as([*]CallFrame, @ptrCast(frame))[1];
                    frame.* = .{
                        .closure = closure,
                        .proto = callee_proto,
                        .base = callee_base,
                        .pc = 0,
                        .return_start = function_slot,
                        .return_count = op.return_count,
                        .varargs = &.{},
                        .debug_name_override = thread.next_call_name,
                        .debug_namewhat_override = thread.next_call_namewhat,
                    };
                    thread.frames.items.len = callee_index + 1;
                    thread.next_call_name = null;
                    thread.next_call_namewhat = null;
                    if (executed_count != 0) {
                        thread.last_result_count = 0;
                        thread.last_transfer_count = 0;
                    }
                    frame_index = callee_index;
                    proto = callee_proto;
                    segment_start = pc +% count_bias +% 1;
                    count_bias = segment_start;
                    pc = 0;
                    base = callee_base;
                    if (self.fastLoopInterrupted()) return true;
                    continue :frames;
                },
                .ret => {
                    const op = instructions[pc].ret;
                    if (frame_index <= return_floor) break :fast_loop;
                    if (op.count == bytecode.multret_count or frame.return_count == bytecode.multret_count or
                        frame.owns_varargs or frame.pending_returns != null) break :fast_loop;
                    if (thread.open_upvalues) |upvalue| if (upvalue.stack_index >= base) break :fast_loop;
                    const return_start = frame.return_start;
                    const return_count = frame.return_count;
                    if (return_start + return_count > stack_limit) break :fast_loop;
                    const executed_count = pc +% count_bias -% segment_start;
                    const copied = @min(return_count, op.count);
                    for (0..copied) |index| thread.stack.items[return_start + index] = stack[op.first + index];
                    @memset(thread.stack.items[return_start + copied .. return_start + return_count], .nil);
                    thread.frames.items.len = frame_index;
                    thread.last_result_base = return_start;
                    thread.last_result_count = return_count;
                    if (executed_count != 0) thread.last_transfer_count = 0;
                    segment_start = pc +% count_bias +% 1;
                    frame_index -= 1;
                    frame = &(@as([*]CallFrame, @ptrCast(frame)) - 1)[0];
                    proto = frame.proto;
                    pc = frame.pc;
                    count_bias = segment_start -% pc;
                    base = frame.base;
                    if (self.fastLoopInterrupted()) return true;
                    continue :frames;
                },
                .close => {
                    const register = instructions[pc].close;
                    const first = base + register;
                    if (thread.open_upvalues) |upvalue| if (upvalue.stack_index >= first) break :fast_loop;
                    pc += 1;
                    if (pc >= instructions.len) break :fast_loop;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                },
                else => break :fast_loop,
            }

            if (pc +% count_bias == segment_start) return segment_start != 0;
            frame.pc = pc;
            thread.last_result_count = 0;
            thread.last_transfer_count = 0;
            return true;
        }
    }

    pub inline fn checkExecutionLimits(self: *State, thread: *Thread) !void {
        return vm_mod.checkExecutionLimits(State, self, thread);
    }

    /// Allocates the shared interrupt control on first use; polling starts at the next safepoint.
    pub fn interruptControl(self: *State) !*vm_mod.InterruptControl {
        if (self.interrupt) |control| return control;
        const control = try self.allocator.create(vm_mod.InterruptControl);
        control.* = .{};
        self.interrupt = control;
        self.instruction_checkpoint = 0;
        return control;
    }

    pub inline fn interruptRequested(self: *const State) bool {
        const control = self.interrupt orelse return false;
        return control.requested.load(.monotonic);
    }

    pub fn clearInterrupt(self: *State) void {
        if (self.interrupt) |control| control.clear();
        self.instruction_checkpoint = 0;
    }

    /// Polled periodically by native functions with long internal loops.
    pub fn checkInterrupt(self: *State) !void {
        return vm_mod.checkInterrupt(State, self);
    }

    inline fn fastLoopInterrupted(self: *State) bool {
        if (!self.interruptRequested()) return false;
        self.instruction_checkpoint = 0;
        return true;
    }

    /// The uncounted fast loop is disabled while any instruction budget applies.
    pub inline fn instructionBudgetActive(self: *const State) bool {
        return self.options.max_instructions != null or self.call_instruction_deadline != null;
    }

    pub fn instructionBudgetUsed(self: *const State) u64 {
        return self.instruction_count -| self.instruction_budget_base;
    }

    /// Restarts the cumulative `max_instructions` budget.
    pub fn resetInstructionBudget(self: *State) void {
        self.instruction_budget_base = self.instruction_count;
        self.instruction_checkpoint = 0;
    }

    /// Limits a host call, including nested calls and coroutines, to `max` further
    /// instructions. Returns the enclosing deadline for `endCallInstructionBudget`.
    pub fn beginCallInstructionBudget(self: *State, max: u64) ?u64 {
        const previous = self.call_instruction_deadline;
        const deadline = self.instruction_count +| max;
        self.call_instruction_deadline = if (previous) |outer| @min(outer, deadline) else deadline;
        self.instruction_checkpoint = 0;
        return previous;
    }

    /// Restores the deadline returned by `beginCallInstructionBudget`.
    pub fn endCallInstructionBudget(self: *State, previous: ?u64) void {
        self.call_instruction_deadline = previous;
        self.instruction_checkpoint = 0;
    }

    fn consumeInterrupt(self: *State) void {
        if (self.interrupt) |control| control.clear();
        self.instruction_checkpoint = 0;
    }

    pub fn noteAllocation(self: *State, bytes: usize) void {
        return gc_mod.noteAllocation(State, self, bytes);
    }

    pub fn noteAllocationFreed(self: *State, bytes: usize) void {
        return gc_mod.noteAllocationFreed(State, self, bytes);
    }

    pub fn refreshAllocationTotal(self: *State) usize {
        return gc_mod.refreshAllocationTotal(State, self);
    }

    pub fn currentAllocationTotal(self: *State) usize {
        return gc_mod.currentAllocationTotal(State, self);
    }

    pub fn tableCapacityBytes(table: *const Table) usize {
        return gc_mod.tableCapacityBytes(table);
    }

    pub fn tableGcBytes(table: *const Table) usize {
        return gc_mod.tableGcBytes(table);
    }

    pub fn noteTableCapacityDelta(self: *State, table: *Table, old_capacity_bytes: usize) void {
        return gc_mod.noteTableCapacityDelta(State, self, table, old_capacity_bytes);
    }

    pub fn setTableRaw(self: *State, table: *Table, key: Value, value: Value) !void {
        const old_capacity_bytes = tableCapacityBytes(table);
        defer self.noteTableCapacityDelta(table, old_capacity_bytes);
        try table.set(self.allocator, key, value);
        self.writeTableBarrier(table, key, value);
    }

    fn fastTableArraySet(self: *State, table_value: Value, key_value: Value, value: Value) !bool {
        if (table_value != .table) return false;
        const index = arrayIndex(key_value) orelse return false;
        if (index > std.math.maxInt(u32)) return false;
        return self.fastTableArraySetIndex(table_value, @intCast(index), value);
    }

    fn fastTableArraySetExistingNoAlloc(self: *State, table_value: Value, key_value: Value, value: Value) bool {
        if (table_value != .table) return false;
        const index = arrayIndex(key_value) orelse return false;
        const table = table_value.table;
        if (table.rollback) |record| if (!record.header.detached) return false;
        if (index <= table.array.items.len) {
            const slot = &table.array.items[index - 1];
            if (slot.* == .nil and !noNewindexMetamethod(table)) return false;
            slot.* = value;
            self.writeTableBarrier(table, key_value, value);
            return true;
        }
        if (value == .nil or !noNewindexMetamethod(table)) return false;
        if (index == table.array.items.len + 1 and index <= table.array.capacity) {
            table.array.appendAssumeCapacity(value);
            table.removeHashKey(key_value);
            self.writeTableBarrier(table, key_value, value);
            return true;
        }
        return false;
    }

    fn fastTableKnownKeySetExistingNoAlloc(self: *State, table_value: Value, key: Value, value: Value) bool {
        if (table_value != .table or key != .string) return false;
        const table = table_value.table;
        if (table.rollback) |record| if (!record.header.detached) return false;
        if (table.findEntry(key)) |index| {
            const slot = &table.entries.items[index].value;
            if (slot.* == .nil) {
                if (!noNewindexMetamethod(table)) return false;
                table.invalidateMetaEvents();
            }
            slot.* = value;
            self.writeTableBarrier(table, key, value);
            return true;
        }
        if (!noNewindexMetamethod(table) or !table.insertHashEntryNoAlloc(key, value)) return false;
        self.writeTableBarrier(table, key, value);
        return true;
    }

    fn fastTableArraySetIndex(self: *State, table_value: Value, index_u32: u32, value: Value) !bool {
        if (table_value != .table or index_u32 == 0) return false;
        const index: usize = index_u32;
        const key_value = Value{ .integer = @intCast(index_u32) };
        const table = table_value.table;
        defer self.noteTableCapacityDelta(table, 0);
        try rollback_mod.tableWritable(table);
        if (index <= table.array.items.len) {
            const slot = &table.array.items[index - 1];
            if (slot.* != .nil or noNewindexMetamethod(table)) {
                slot.* = value;
                self.writeTableBarrier(table, key_value, value);
                return true;
            }
            return false;
        }
        if (value == .nil or !noNewindexMetamethod(table)) return false;
        if (index == table.array.items.len + 1) {
            const old_capacity_bytes = tableCapacityBytes(table);
            try table.array.append(self.allocator, value);
            table.removeHashKey(key_value);
            self.noteTableCapacityDelta(table, old_capacity_bytes);
            self.writeTableBarrier(table, key_value, value);
            return true;
        }
        if (index > table.array.capacity) return false;

        const old_capacity_bytes = tableCapacityBytes(table);
        const old_len = table.array.items.len;
        try table.array.resize(self.allocator, index);
        @memset(table.array.items[old_len..], .nil);
        table.array.items[index - 1] = value;
        table.removeHashKey(key_value);
        self.noteTableCapacityDelta(table, old_capacity_bytes);
        self.writeTableBarrier(table, key_value, value);
        return true;
    }

    fn setTableArrayRawIndex(self: *State, table: *Table, index_u32: u32, value: Value) !void {
        defer self.noteTableCapacityDelta(table, 0);
        try rollback_mod.tableWritable(table);
        const index: usize = index_u32;
        const key = Value{ .integer = @intCast(index_u32) };
        if (index <= table.array.items.len) {
            table.array.items[index - 1] = value;
            self.writeTableBarrier(table, key, value);
            return;
        }
        if (value == .nil) return;
        if (index == table.array.items.len + 1) {
            const old_capacity_bytes = tableCapacityBytes(table);
            try table.array.append(self.allocator, value);
            self.noteTableCapacityDelta(table, old_capacity_bytes);
            self.writeTableBarrier(table, key, value);
            return;
        }
        if (index <= table.array.capacity) {
            const old_capacity_bytes = tableCapacityBytes(table);
            const old_len = table.array.items.len;
            try table.array.resize(self.allocator, index);
            @memset(table.array.items[old_len..], .nil);
            table.array.items[index - 1] = value;
            self.noteTableCapacityDelta(table, old_capacity_bytes);
            self.writeTableBarrier(table, key, value);
            return;
        }
        try self.setTableRaw(table, key, value);
        self.writeTableBarrier(table, key, value);
    }

    fn fastTableKnownKeySet(self: *State, table_value: Value, key: Value, value: Value) !bool {
        if (table_value != .table) return false;
        const table = table_value.table;
        if (table.rollback != null and table.get(key) != .nil) {
            try rollback_mod.tableWritable(table);
            self.noteTableCapacityDelta(table, 0);
        }
        if (table.setExistingNonNil(key, value)) {
            self.writeTableBarrier(table, key, value);
            return true;
        }
        if (!noNewindexMetamethod(table)) return false;
        if (value == .nil) return true;
        try self.setTableRaw(table, key, value);
        self.writeTableBarrier(table, key, value);
        return true;
    }

    fn traceInstruction(self: *State, frame: CallFrame, pc: usize, instruction: bytecode.Instruction) !void {
        const line = if (pc < frame.proto.line_info.items.len) frame.proto.line_info.items[pc].line else 0;
        try appendFmt(self.allocator, &self.stderr, "[trace-vm] {s}:{d} pc={d} op={s}\n", .{ frame.proto.source_name, line, pc, @tagName(instruction) });
    }

    fn get(_: *State, thread: *Thread, register: usize) Value {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        return thread.stack.items[frame.base + register];
    }

    fn declareGlobal(self: *State, thread: *Thread, name: []const u8, table_register: bytecode.Register, value_register: bytecode.Register) !void {
        const table_value = self.get(thread, table_register);
        if (table_value != .table) return self.failRuntimeDetail(thread, "attempt to index a nil value");
        const key = Value{ .string = try self.intern(name) };
        if (table_value.table.get(key) != .nil) {
            const message = try std.fmt.allocPrint(self.allocator, "global '{s}' already defined", .{name});
            defer self.allocator.free(message);
            return self.fail(try self.intern(message));
        }
        try self.setTable(table_value, key, self.get(thread, value_register));
    }

    fn set(_: *State, thread: *Thread, register: usize, value: Value) void {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        thread.stack.items[frame.base + register] = value;
    }

    fn absoluteRegister(_: *State, thread: *Thread, register: usize) usize {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        return frame.base + @as(usize, register);
    }

    fn setGlobal(self: *State, name: []const u8, value: Value) !void {
        const table = self.global_table orelse return error.RuntimeError;
        const key = try self.intern(name);
        try self.setTableRaw(table, .{ .string = key }, value);
        self.writeTableBarrier(table, .{ .string = key }, value);
        self.markValue(value);
    }

    fn getGlobalValue(self: *State, name: []const u8) Value {
        const table = self.global_table orelse return .nil;
        return table.get(.{ .string = name });
    }

    pub fn getGlobal(self: *State, name: []const u8) Value {
        return self.getGlobalValue(name);
    }

    pub fn currentLine(self: *State, thread: *Thread, level: i64) ?usize {
        _ = self;
        if (level < 1) return null;
        const depth: usize = @intCast(level);
        if (depth > thread.frames.items.len) return null;
        const frame = thread.frames.items[thread.frames.items.len - depth];
        if (frame.proto.line_info.items.len == 0) return null;
        const pc = if (frame.pc == 0) @as(usize, 0) else frame.pc - 1;
        return frame.proto.line_info.items[@min(pc, frame.proto.line_info.items.len - 1)].line;
    }

    pub fn currentExtraArgs(self: *State, thread: *Thread, level: i64) ?usize {
        _ = self;
        if (level < 1) return null;
        const depth: usize = @intCast(level);
        if (depth > thread.frames.items.len) return null;
        const frame = thread.frames.items[thread.frames.items.len - depth];
        return frame.varargs.len;
    }

    pub fn currentWhat(self: *State, thread: *Thread, level: i64) []const u8 {
        _ = self;
        if (level == 2 and thread.protected_close_depth != 0) return "C";
        if (level >= 1) {
            const depth: usize = @intCast(level);
            if (depth <= thread.frames.items.len) {
                const frame = thread.frames.items[thread.frames.items.len - depth];
                if (frame.proto.defined_line == 0) return "main";
            }
        }
        return "Lua";
    }

    pub fn currentFunctionName(self: *State, thread: *Thread, level: i64) ?[]const u8 {
        _ = self;
        if (level == 2 and thread.protected_close_depth != 0) return "pcall";
        if (level == 2 and thread.hook_running) if (thread.hook_return_name) |name| return name;
        if (level < 1) return null;
        const depth: usize = @intCast(level);
        if (depth > thread.frames.items.len) return null;
        const frame = thread.frames.items[thread.frames.items.len - depth];
        const pc = if (frame.pc == 0) 0 else frame.pc - 1;
        for (frame.proto.locals.items) |local| {
            if (!std.mem.eql(u8, local.name, "name")) continue;
            if (pc < local.start_pc or (local.end_pc != 0 and pc > local.end_pc)) continue;
            const value = thread.stack.items[frame.base + local.register];
            if (value == .string) return value.string;
        }
        return frame.debug_name_override orelse frame.proto.debug_name;
    }

    pub fn currentFunctionNameWhat(self: *State, thread: *Thread, level: i64) ?[]const u8 {
        _ = self;
        if (level < 1) return null;
        const depth: usize = @intCast(level);
        if (depth > thread.frames.items.len) return null;
        const frame = thread.frames.items[thread.frames.items.len - depth];
        return frame.debug_namewhat_override;
    }

    pub fn setThreadHook(self: *State, target: *Thread, hook: Value, mask: []const u8, count: u32) void {
        rollback_mod.touch(target);
        target.hook = hook;
        self.writeBarrier(target, hook);
        target.hook_call = false;
        target.hook_line = false;
        target.hook_return = false;
        target.hook_count = 0;
        target.hook_count_remaining = 0;
        target.pending_yield_hook_return = false;
        if (hook == .nil) return;
        target.hook_call = std.mem.indexOfScalar(u8, mask, 'c') != null;
        target.hook_line = std.mem.indexOfScalar(u8, mask, 'l') != null;
        target.hook_return = std.mem.indexOfScalar(u8, mask, 'r') != null;
        target.hook_count = count;
        target.hook_count_remaining = hookDispatchInterval(count);
        if (target.hook_line and target.frames.items.len != 0) {
            const frame_index = target.frames.items.len - 1;
            target.frames.items[frame_index].last_hook_line = lineForFrame(target.frames.items[frame_index]);
        }
    }

    pub fn threadHookMask(self: *State, thread: *Thread) ![]const u8 {
        var bytes: [3]u8 = undefined;
        var len: usize = 0;
        if (thread.hook_call) {
            bytes[len] = 'c';
            len += 1;
        }
        if (thread.hook_return) {
            bytes[len] = 'r';
            len += 1;
        }
        if (thread.hook_line) {
            bytes[len] = 'l';
            len += 1;
        }
        return self.intern(bytes[0..len]);
    }

    pub fn callHook(self: *State, thread: *Thread, event: []const u8) !void {
        const args = [_]Value{.{ .string = try self.intern(event) }};
        try self.callHookWithArgs(thread, &args);
    }

    fn callReturnHook(self: *State, thread: *Thread, name: ?[]const u8) !void {
        const previous = thread.hook_return_name;
        thread.hook_return_name = name;
        defer thread.hook_return_name = previous;
        try self.callHook(thread, "return");
    }

    fn callHookWithArgs(self: *State, thread: *Thread, args: []const Value) !void {
        if (thread.hook == .nil or thread.hook_running) return;
        thread.hook_running = true;
        defer thread.hook_running = false;
        self.conservative_gc_depth += 1;
        defer self.conservative_gc_depth -= 1;
        const previous_result_base = thread.last_result_base;
        const previous_result_count = thread.last_result_count;
        defer {
            thread.last_result_base = previous_result_base;
            thread.last_result_count = previous_result_count;
        }
        _ = try call_mod.callOneNamed(State, self, thread, "?", "hook", thread.hook, args);
    }

    fn callLineHook(self: *State, thread: *Thread) !void {
        if (!thread.hook_line or thread.hook == .nil or thread.hook_running) return;
        if (thread.frames.items.len == 0) return;
        const frame_index = thread.frames.items.len - 1;
        const line = lineForFrame(thread.frames.items[frame_index]) orelse return;
        if (thread.frames.items[frame_index].last_hook_line == line) return;
        thread.frames.items[frame_index].last_hook_line = line;
        const line_value = if (thread.frames.items[frame_index].closure.stripped_debug) Value.nil else Value{ .integer = @intCast(line) };
        const args = [_]Value{ .{ .string = try self.intern("line") }, line_value };
        try self.callHookWithArgs(thread, &args);
    }

    fn callCountHook(self: *State, thread: *Thread) !void {
        if (thread.hook_count == 0 or thread.hook == .nil or thread.hook_running) return;
        if (thread.hook_count_remaining > 1) {
            thread.hook_count_remaining -= 1;
            return;
        }
        thread.hook_count_remaining = hookDispatchInterval(thread.hook_count);
        try self.callHook(thread, "count");
    }

    fn hookDispatchInterval(count: u32) u32 {
        return if (count == 0) 0 else count * 2;
    }

    pub fn putGlobal(self: *State, name: []const u8, value: Value) !void {
        try self.setGlobal(name, value);
    }

    pub fn rootValue(self: *State, value: Value) !usize {
        for (self.api_roots.items, 0..) |root, index| {
            if (root == .nil) {
                self.api_roots.items[index] = value;
                self.markValue(value);
                return index;
            }
        }
        try self.api_roots.append(self.allocator, value);
        self.markValue(value);
        return self.api_roots.items.len - 1;
    }

    pub fn unrootValue(self: *State, index: usize) void {
        if (index < self.api_roots.items.len) self.api_roots.items[index] = .nil;
    }

    pub fn pushValueRoots(self: *State, roots: *types.ValueRoots, values: []const Value) void {
        roots.* = .{ .values = values, .previous = self.value_roots };
        self.value_roots = roots;
    }

    pub fn popValueRoots(self: *State, roots: *types.ValueRoots) void {
        std.debug.assert(self.value_roots == roots);
        self.value_roots = roots.previous;
    }

    pub fn rootedValue(self: *const State, index: usize) Value {
        if (index >= self.api_roots.items.len) return .nil;
        return self.api_roots.items[index];
    }

    pub fn activeRootCount(self: State) usize {
        var count: usize = 0;
        for (self.api_roots.items) |root| {
            if (root != .nil) count += 1;
        }
        return count;
    }

    pub fn setApiCallbackDispatch(self: *State, dispatch: ApiCallbackDispatchFn, user_data: *anyopaque) void {
        self.api_callback_dispatch = dispatch;
        self.api_callback_user_data = user_data;
    }

    pub fn callApiCallbackDispatch(self: *State, thread: *Thread, op: bytecode.Call, callback_id: usize) !void {
        const dispatch = self.api_callback_dispatch orelse return self.fail("host callback dispatcher unavailable");
        var context = ApiCallbackContext{
            .state = self,
            .thread = thread,
            .op = op,
            .callback_id = callback_id,
            .argument_base = thread.frames.items[thread.frames.items.len - 1].base + op.base + 1,
            .parent = self.active_api_callback,
            .user_data = self.api_callback_user_data,
        };
        defer context.deinit();
        self.active_api_callback = &context;
        defer self.active_api_callback = context.parent;

        dispatch(&context) catch |err| switch (err) {
            error.HostCallbackYield => return coroutine_mod.suspendCoroutine(State, self, thread, op, context.returns.items()),
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => return err,
            error.LuaError => return self.failValue(context.error_value orelse .{ .string = try self.intern("host callback raised an error") }),
            error.OutOfMemory, error.LuaExit, error.Interrupted => return err,
            else => return self.fail(@errorName(err)),
        };

        try self.returnValues(thread, op.base, op.return_count, context.returns.items());
    }

    /// Failures raise PUC `loadfile`-style messages such as "cannot open name.lua: No such file or directory".
    pub fn readFileAlloc(self: *State, path: []const u8) ![]const u8 {
        return self.readFileRaw(path) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            const info = host.fileError(err);
            const message = if (err == error.IsDir)
                try std.fmt.allocPrint(self.allocator, "cannot read {s}", .{path})
            else
                try std.fmt.allocPrint(self.allocator, "cannot {s} {s}: {s}", .{ if (info.read_phase) "read" else "open", path, info.message });
            defer self.allocator.free(message);
            return self.fail(try self.intern(message));
        };
    }

    /// Like `readFileAlloc`, but returns filesystem errors unchanged.
    pub fn readFileRaw(self: *State, path: []const u8) anyerror![]const u8 {
        return self.fsReadFileAlloc(path, self.options.max_file_bytes);
    }

    /// Raises "<path>: <strerror message>" for a failed file operation.
    pub fn failFileOperation(self: *State, path: []const u8, err: anyerror) anyerror {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const message = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ path, host.fileError(err).message });
        defer self.allocator.free(message);
        return self.fail(try self.intern(message));
    }

    pub fn writeStdout(self: *State, bytes: []const u8) !void {
        if (self.options.capture_output) {
            if (self.rollback) |journal| try journal.outputWritable(self);
            try self.stdout.appendSlice(self.allocator, bytes);
        }
        if (self.options.stdout) |writer| try writeOutput(writer, self.options.stdout_flush, bytes);
    }

    /// Emits one warning made of `parts`, like continued `lua_warning` calls. A single
    /// part starting with `@` is a control message.
    pub fn warn(self: *State, parts: []const []const u8) !void {
        if (parts.len == 1 and std.mem.startsWith(u8, parts[0], "@")) {
            const control = parts[0][1..];
            if (std.mem.eql(u8, control, "on")) self.warnings_on = true;
            if (std.mem.eql(u8, control, "off")) self.warnings_on = false;
            return;
        }
        if (!self.warnings_on) return;
        if (self.options.warning_handler) |handler| {
            const message = try std.mem.concat(self.allocator, u8, parts);
            defer self.allocator.free(message);
            handler.emit(handler.context, message);
            return;
        }
        try self.writeStderr("Lua warning: ");
        for (parts) |part| try self.writeStderr(part);
        try self.writeStderr("\n");
    }

    /// Like `luaE_warnerror`: warns `error in <where> (<message>)`.
    pub fn warnError(self: *State, where: []const u8, error_value: Value) void {
        const message = switch (error_value) {
            .string => |text| text,
            .nil => "<no error object>",
            else => "error object is not a string",
        };
        self.warn(&.{ "error in ", where, " (", message, ")" }) catch {};
    }

    pub fn writeStderr(self: *State, bytes: []const u8) !void {
        if (self.options.capture_output) {
            if (self.rollback) |journal| try journal.outputWritable(self);
            try self.stderr.appendSlice(self.allocator, bytes);
        }
        if (self.options.stderr) |writer| try writeOutput(writer, self.options.stderr_flush, bytes);
    }

    fn writeOutput(writer: *std.Io.Writer, policy: OutputFlush, bytes: []const u8) !void {
        try writer.writeAll(bytes);
        switch (policy) {
            .explicit, .print => {},
            .line => if (std.mem.indexOfScalar(u8, bytes, '\n') != null) try writer.flush(),
            .always => try writer.flush(),
        }
    }

    fn flushStdoutAfterPrint(self: *State) !void {
        if (self.options.stdout_flush == .print) try self.flushStdout();
    }

    /// Flushes line-buffered or unbuffered stdout before blocking on stdin, as C stdio does.
    pub fn flushStdoutForInput(self: *State) void {
        switch (self.options.stdout_flush) {
            .explicit, .print => {},
            .line, .always => self.flushStdout() catch {},
        }
    }

    pub fn flushStdout(self: *State) !void {
        if (self.options.stdout) |writer| try writer.flush();
    }

    pub fn flushStderr(self: *State) !void {
        if (self.options.stderr) |writer| try writer.flush();
    }

    pub fn writeFile(self: *State, path: []const u8, data: []const u8) !void {
        self.fsWriteFile(path, data) catch |err| return self.failFileOperation(path, err);
    }

    pub fn removeFile(self: *State, path: []const u8) !void {
        self.fsRemovePath(path, false) catch |err| return self.failFileOperation(path, err);
    }

    pub fn renameFile(self: *State, old_path: []const u8, new_path: []const u8) !void {
        self.fsRenamePath(old_path, new_path) catch |err| return self.failFileOperation(old_path, err);
    }

    /// Also capped by `max_file_bytes`.
    pub fn fsReadFileAlloc(self: *State, path: []const u8, requested_max_bytes: usize) anyerror![]const u8 {
        const max_bytes = @min(requested_max_bytes, self.options.max_file_bytes);
        switch (self.options.filesystem) {
            .disabled => return error.FilesystemDisabled,
            .memory => |files| {
                const normalized = try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
                defer self.allocator.free(normalized);
                for (files) |file| {
                    if (std.mem.eql(u8, file.path, normalized)) {
                        if (file.contents.len > max_bytes) return error.StreamTooLong;
                        return self.allocator.dupe(u8, file.contents);
                    }
                }
                for (files) |file| {
                    if (file.path.len > normalized.len and std.mem.startsWith(u8, file.path, normalized) and file.path[normalized.len] == '/') return error.IsDir;
                }
                return error.FileNotFound;
            },
            .memory_rw => |filesystem| {
                const bytes = try filesystem.readFileAlloc(self.allocator, path);
                if (bytes.len > max_bytes) {
                    self.allocator.free(bytes);
                    return error.StreamTooLong;
                }
                return bytes;
            },
            .custom => |filesystem| {
                const bytes = try filesystem.read_file_alloc(filesystem.context, self.allocator, path);
                if (bytes.len > max_bytes) {
                    self.allocator.free(bytes);
                    return error.StreamTooLong;
                }
                return bytes;
            },
            .host_cwd => if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
                const io = self.options.io orelse return error.IoUnavailable;
                return Dir.cwd().readFileAlloc(io, path, self.allocator, .limited(max_bytes));
            },
            .host_dir => |root| if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
                const io = self.options.io orelse return error.IoUnavailable;
                const normalized = try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
                defer self.allocator.free(normalized);
                return root.dir.readFileAlloc(io, normalized, self.allocator, .limited(max_bytes));
            },
        }
    }

    pub fn fsWriteFile(self: *State, path: []const u8, data: []const u8) anyerror!void {
        self.file_generation +%= 1;
        switch (self.options.filesystem) {
            .disabled, .memory => return error.FilesystemReadOnly,
            .memory_rw => |filesystem| return filesystem.writeFile(path, data),
            .custom => |filesystem| {
                const write = filesystem.write_file orelse return error.OperationUnsupported;
                return write(filesystem.context, path, data);
            },
            .host_cwd => if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
                const io = self.options.io orelse return error.IoUnavailable;
                return Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
            },
            .host_dir => |root| if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
                if (root.read_only) return error.FilesystemReadOnly;
                const io = self.options.io orelse return error.IoUnavailable;
                const normalized = try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
                defer self.allocator.free(normalized);
                return root.dir.writeFile(io, .{ .sub_path = normalized, .data = data });
            },
        }
    }

    /// Reserves a new empty file like `mkstemp`, failing with `error.PathAlreadyExists`.
    /// Only host filesystems create exclusively; others check first.
    pub fn fsCreateFileExclusive(self: *State, path: []const u8) anyerror!void {
        switch (self.options.filesystem) {
            .disabled => return error.FilesystemDisabled,
            .memory => return error.FilesystemReadOnly,
            .memory_rw => |filesystem| {
                if (filesystem.statPath(path)) |_| return error.PathAlreadyExists else |err| if (err != error.FileNotFound) return err;
                try filesystem.writeFile(path, "");
            },
            .custom => |filesystem| {
                const write = filesystem.write_file orelse return error.OperationUnsupported;
                if (filesystem.stat) |stat| {
                    if (stat(filesystem.context, path, false)) |_| return error.PathAlreadyExists else |err| if (err != error.FileNotFound) return err;
                } else if (filesystem.read_file_alloc(filesystem.context, self.allocator, path)) |bytes| {
                    self.allocator.free(bytes);
                    return error.PathAlreadyExists;
                } else |err| switch (err) {
                    error.FileNotFound => {},
                    error.IsDir => return error.PathAlreadyExists,
                    else => return err,
                }
                try write(filesystem.context, path, "");
            },
            .host_cwd => if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
                const io = self.options.io orelse return error.IoUnavailable;
                const file = if (std.fs.path.isAbsolute(path))
                    try Dir.createFileAbsolute(io, path, .{ .exclusive = true })
                else
                    try Dir.cwd().createFile(io, path, .{ .exclusive = true });
                file.close(io);
            },
            .host_dir => |root| if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
                if (root.read_only) return error.FilesystemReadOnly;
                const io = self.options.io orelse return error.IoUnavailable;
                const normalized = try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
                defer self.allocator.free(normalized);
                const file = try root.dir.createFile(io, normalized, .{ .exclusive = true });
                file.close(io);
            },
        }
        self.file_generation +%= 1;
    }

    /// Writes into an existing file without truncating it. Returns `error.OperationUnsupported`
    /// without positional writes; callers then fall back to `fsWriteFile`.
    pub fn fsWriteFileAt(self: *State, path: []const u8, offset: usize, data: []const u8) anyerror!void {
        return self.fsWritePositioned(path, offset, data);
    }

    /// Custom filesystems lack positional writes, so the whole file is rewritten.
    pub fn fsAppendFile(self: *State, path: []const u8, data: []const u8) anyerror!void {
        if (self.options.filesystem != .custom) return self.fsWritePositioned(path, null, data);
        const old = try self.readFileRaw(path);
        defer self.allocator.free(old);
        const joined = try std.mem.concat(self.allocator, u8, &.{ old, data });
        defer self.allocator.free(joined);
        try self.fsWriteFile(path, joined);
    }

    /// A null `offset` appends.
    fn fsWritePositioned(self: *State, path: []const u8, offset: ?usize, data: []const u8) anyerror!void {
        switch (self.options.filesystem) {
            .disabled, .memory => return error.FilesystemReadOnly,
            .memory_rw => |filesystem| {
                const position = offset orelse std.math.cast(usize, (try filesystem.statPath(path)).size) orelse return error.FileTooBig;
                try filesystem.writeAt(path, position, data);
                self.file_generation +%= 1;
            },
            .custom => return error.OperationUnsupported,
            .host_cwd, .host_dir => {
                if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
                const io = self.options.io orelse return error.IoUnavailable;
                const root: Dir = switch (self.options.filesystem) {
                    .host_cwd => Dir.cwd(),
                    .host_dir => |value| blk: {
                        if (value.read_only) return error.FilesystemReadOnly;
                        break :blk value.dir;
                    },
                    else => unreachable,
                };
                const owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len) else null;
                defer if (owned) |normalized| self.allocator.free(normalized);
                const sub_path = owned orelse path;
                // Zig 0.16 sizes a Windows handle with a query write-only handles may not make.
                const position: u64 = offset orelse (try root.statFile(io, sub_path, .{})).size;
                var file = try root.openFile(io, sub_path, .{ .mode = .write_only, .allow_directory = false });
                defer file.close(io);
                self.file_generation +%= 1;
                try file.writePositionalAll(io, data, position);
            },
        }
    }

    /// Checks an existing file is writable without changing it, as `fopen` does for append modes.
    pub fn fsCheckWritable(self: *State, path: []const u8) anyerror!void {
        switch (self.options.filesystem) {
            .custom => |filesystem| if (filesystem.write_file == null) return error.OperationUnsupported,
            else => try self.fsWriteFileAt(path, 0, ""),
        }
    }

    pub fn fsStat(self: *State, path: []const u8, follow_symlinks: bool) anyerror!host.FileStat {
        switch (self.options.filesystem) {
            .disabled => return error.FilesystemDisabled,
            .memory => |files| {
                var view = try host.MemoryFilesystem.initWithFiles(self.allocator, files);
                defer view.deinit();
                return view.statPath(path);
            },
            .memory_rw => |filesystem| return filesystem.statPath(path),
            .custom => |filesystem| {
                const stat = filesystem.stat orelse return error.OperationUnsupported;
                return stat(filesystem.context, path, follow_symlinks);
            },
            .host_cwd => if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
                const io = self.options.io orelse return error.IoUnavailable;
                return .fromStd(try Dir.cwd().statFile(io, path, .{ .follow_symlinks = follow_symlinks }));
            },
            .host_dir => |root| if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
                const io = self.options.io orelse return error.IoUnavailable;
                const normalized = try host.MemoryFilesystem.normalizeRootPathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
                defer self.allocator.free(normalized);
                if (normalized.len == 0) return .fromStd(try root.dir.stat(io));
                return .fromStd(try root.dir.statFile(io, normalized, .{ .follow_symlinks = follow_symlinks }));
            },
        }
    }

    pub fn fsReadDirAlloc(self: *State, path: []const u8) anyerror![]host.DirectoryEntry {
        switch (self.options.filesystem) {
            .disabled => return error.FilesystemDisabled,
            .memory => |files| {
                var view = try host.MemoryFilesystem.initWithFiles(self.allocator, files);
                defer view.deinit();
                return view.readDirAlloc(self.allocator, path);
            },
            .memory_rw => |filesystem| return filesystem.readDirAlloc(self.allocator, path),
            .custom => |filesystem| {
                const read_dir = filesystem.read_dir_alloc orelse return error.OperationUnsupported;
                return read_dir(filesystem.context, self.allocator, path);
            },
            .host_cwd, .host_dir => {
                if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
                const io = self.options.io orelse return error.IoUnavailable;
                const base: Dir = switch (self.options.filesystem) {
                    .host_cwd => Dir.cwd(),
                    .host_dir => |root| root.dir,
                    else => unreachable,
                };
                const owned_path = if (self.options.filesystem == .host_dir)
                    try host.MemoryFilesystem.normalizeRootPathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len)
                else
                    null;
                defer if (owned_path) |normalized| self.allocator.free(normalized);
                const open_path = if (owned_path) |normalized| if (normalized.len == 0) "." else normalized else path;
                var dir = try base.openDir(io, open_path, .{ .iterate = true });
                defer dir.close(io);
                var iterator = dir.iterate();
                var entries: std.ArrayList(host.DirectoryEntry) = .empty;
                errdefer {
                    for (entries.items) |entry| self.allocator.free(entry.name);
                    entries.deinit(self.allocator);
                }
                while (try iterator.next(io)) |entry| {
                    try entries.append(self.allocator, .{
                        .name = try self.allocator.dupe(u8, entry.name),
                        .kind = .fromStd(entry.kind),
                        .inode = @intCast(entry.inode),
                    });
                }
                return entries.toOwnedSlice(self.allocator);
            },
        }
    }

    pub fn fsMakeDir(self: *State, path: []const u8, parents: bool) anyerror!void {
        switch (self.options.filesystem) {
            .disabled, .memory => return error.FilesystemReadOnly,
            .memory_rw => |filesystem| return filesystem.makeDir(path, parents),
            .custom => |filesystem| {
                const make_dir = filesystem.make_dir orelse return error.OperationUnsupported;
                return make_dir(filesystem.context, path, parents);
            },
            .host_cwd, .host_dir => {
                if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
                const root: Dir = switch (self.options.filesystem) {
                    .host_cwd => Dir.cwd(),
                    .host_dir => |value| blk: {
                        if (value.read_only) return error.FilesystemReadOnly;
                        break :blk value.dir;
                    },
                    else => unreachable,
                };
                const io = self.options.io orelse return error.IoUnavailable;
                const owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len) else null;
                defer if (owned) |normalized| self.allocator.free(normalized);
                const actual = owned orelse path;
                if (parents) return root.createDirPath(io, actual);
                return root.createDir(io, actual, .default_dir);
            },
        }
    }

    pub fn fsRemovePath(self: *State, path: []const u8, recursive: bool) anyerror!void {
        self.file_generation +%= 1;
        switch (self.options.filesystem) {
            .disabled, .memory => return error.FilesystemReadOnly,
            .memory_rw => |filesystem| return filesystem.removePath(path, recursive),
            .custom => |filesystem| {
                if (filesystem.remove_path) |remove_path| return remove_path(filesystem.context, path, recursive);
                if (!recursive) if (filesystem.remove_file) |remove_file| return remove_file(filesystem.context, path);
                return error.OperationUnsupported;
            },
            .host_cwd, .host_dir => {
                if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
                const root: Dir = switch (self.options.filesystem) {
                    .host_cwd => Dir.cwd(),
                    .host_dir => |value| blk: {
                        if (value.read_only) return error.FilesystemReadOnly;
                        break :blk value.dir;
                    },
                    else => unreachable,
                };
                const io = self.options.io orelse return error.IoUnavailable;
                const owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len) else null;
                defer if (owned) |normalized| self.allocator.free(normalized);
                const actual = owned orelse path;
                if (recursive) return root.deleteTree(io, actual);
                const stat = try root.statFile(io, actual, .{ .follow_symlinks = false });
                return if (stat.kind == .directory) root.deleteDir(io, actual) else root.deleteFile(io, actual);
            },
        }
    }

    pub fn fsRenamePath(self: *State, old_path: []const u8, new_path: []const u8) anyerror!void {
        self.file_generation +%= 1;
        switch (self.options.filesystem) {
            .disabled, .memory => return error.FilesystemReadOnly,
            .memory_rw => |filesystem| return filesystem.renamePath(old_path, new_path),
            .custom => |filesystem| {
                const rename = filesystem.rename_file orelse return error.OperationUnsupported;
                return rename(filesystem.context, old_path, new_path);
            },
            .host_cwd, .host_dir => {
                if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
                const root: Dir = switch (self.options.filesystem) {
                    .host_cwd => Dir.cwd(),
                    .host_dir => |value| blk: {
                        if (value.read_only) return error.FilesystemReadOnly;
                        break :blk value.dir;
                    },
                    else => unreachable,
                };
                const io = self.options.io orelse return error.IoUnavailable;
                const old_owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, old_path, host.MemoryFilesystem.default_max_path_len) else null;
                defer if (old_owned) |normalized| self.allocator.free(normalized);
                const new_owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, new_path, host.MemoryFilesystem.default_max_path_len) else null;
                defer if (new_owned) |normalized| self.allocator.free(normalized);
                return root.rename(old_owned orelse old_path, root, new_owned orelse new_path, io);
            },
        }
    }

    pub fn fsCopyFile(self: *State, source: []const u8, destination: []const u8, overwrite: bool) anyerror!void {
        self.file_generation +%= 1;
        switch (self.options.filesystem) {
            .disabled, .memory => return error.FilesystemReadOnly,
            .memory_rw => |filesystem| return filesystem.copyFile(source, destination, overwrite),
            .custom => |filesystem| {
                if (filesystem.copy_file) |copy| return copy(filesystem.context, source, destination, overwrite);
                const bytes = try filesystem.read_file_alloc(filesystem.context, self.allocator, source);
                defer self.allocator.free(bytes);
                const write = filesystem.write_file orelse return error.OperationUnsupported;
                return write(filesystem.context, destination, bytes);
            },
            .host_cwd, .host_dir => {
                if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
                const root: Dir = switch (self.options.filesystem) {
                    .host_cwd => Dir.cwd(),
                    .host_dir => |value| blk: {
                        if (value.read_only) return error.FilesystemReadOnly;
                        break :blk value.dir;
                    },
                    else => unreachable,
                };
                const io = self.options.io orelse return error.IoUnavailable;
                const source_owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, source, host.MemoryFilesystem.default_max_path_len) else null;
                defer if (source_owned) |normalized| self.allocator.free(normalized);
                const destination_owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, destination, host.MemoryFilesystem.default_max_path_len) else null;
                defer if (destination_owned) |normalized| self.allocator.free(normalized);
                return root.copyFile(source_owned orelse source, root, destination_owned orelse destination, io, .{ .replace = overwrite });
            },
        }
    }

    pub fn getenv(self: *State, name: []const u8) ?[]const u8 {
        return switch (self.options.environment) {
            .disabled => null,
            .map => |environment| environment.get(name),
            .custom => |environment| environment.get(environment.context, name),
        };
    }

    pub fn currentTime(self: *State) !i64 {
        return switch (self.options.clock) {
            .disabled => self.fail("clock access disabled"),
            .fixed => |value| value,
            .system => if (comptime builtin.os.tag == .freestanding) {
                return self.fail("host clock unavailable");
            } else {
                const io = try self.requireIo("clock I/O unavailable");
                return @intCast(@divTrunc(Clock.real.now(io).nanoseconds, std.time.ns_per_s));
            },
            .fixed_local => |clock| clock.now,
            .custom => |clock| clock.now(clock.context) catch return self.fail("clock unavailable"),
        };
    }

    /// Processor seconds for `os.clock`; 0 for a disabled or fixed clock.
    pub fn cpuTime(self: *State) !f64 {
        return switch (self.options.clock) {
            .disabled, .fixed => 0,
            .fixed_local => |clock| clock.cpu_seconds,
            .system => if (comptime builtin.os.tag == .freestanding) {
                return self.fail("host clock unavailable");
            } else {
                const io = try self.requireIo("clock I/O unavailable");
                const nanoseconds: f64 = @floatFromInt(Clock.cpu_process.now(io).nanoseconds);
                return nanoseconds / std.time.ns_per_s;
            },
            .custom => |clock| if (clock.cpu) |cpu| cpu(clock.context) catch return self.fail("clock unavailable") else 0,
        };
    }

    /// Clocks without a time zone use UTC.
    pub fn localOffset(self: *State, timestamp: i64) !timezone.LocalOffset {
        return switch (self.options.clock) {
            .disabled, .fixed => .{},
            .fixed_local => |clock| .{ .offset = clock.utc_offset, .is_dst = clock.is_dst },
            .system => (try self.systemZone()).offsetAt(timestamp),
            .custom => |clock| if (clock.utc_offset) |utc_offset| blk: {
                const result = utc_offset(clock.context, timestamp) catch return self.fail("clock unavailable");
                break :blk .{ .offset = result.offset, .is_dst = result.is_dst };
            } else .{},
        };
    }

    fn localOffsetCallback(self: *State, timestamp: i64) anyerror!timezone.LocalOffset {
        return self.localOffset(timestamp);
    }

    /// Converts local wall-clock seconds to a Unix timestamp, like `mktime`.
    pub fn localToUtc(self: *State, local: i64, is_dst: ?bool) !i64 {
        return timezone.localToUtc(self, localOffsetCallback, local, is_dst);
    }

    fn systemZone(self: *State) !*const timezone.Zone {
        if (self.local_zone) |zone| return zone;
        const zone = try self.allocator.create(timezone.Zone);
        errdefer self.allocator.destroy(zone);
        zone.* = try self.loadSystemZone();
        self.local_zone = zone;
        return zone;
    }

    fn loadSystemZone(self: *State) !timezone.Zone {
        const utc = timezone.Zone.utc(self.allocator);
        if (comptime builtin.os.tag == .freestanding or builtin.os.tag == .windows or builtin.os.tag == .wasi) return utc;
        const io = self.options.io orelse return utc;
        var spec = self.getenv("TZ") orelse "/etc/localtime";
        if (spec.len == 0) return utc;
        if (spec[0] == ':') spec = spec[1..];
        if (spec.len != 0 and std.mem.indexOf(u8, spec, "..") == null) {
            const path = if (spec[0] == '/')
                try self.allocator.dupe(u8, spec)
            else
                try std.fmt.allocPrint(self.allocator, "/usr/share/zoneinfo/{s}", .{spec});
            defer self.allocator.free(path);
            if (Dir.cwd().readFileAlloc(io, path, self.allocator, .limited(1024 * 1024))) |bytes| {
                defer self.allocator.free(bytes);
                if (timezone.Zone.parseTzif(self.allocator, bytes)) |zone| return zone else |err| if (err == error.OutOfMemory) return err;
            } else |err| if (err == error.OutOfMemory) return err;
        }
        return timezone.Zone.fromRule(self.allocator, spec) orelse utc;
    }

    pub fn executeProcess(self: *State, command: []const u8) !ProcessResult {
        return switch (self.options.process) {
            .disabled => return self.fail("process access disabled"),
            .custom => |process| return process.execute(process.context, command) catch return self.fail("process execution failed"),
            .enabled => if (comptime builtin.os.tag == .freestanding) {
                return self.fail("host process unavailable");
            } else {
                const io = try self.requireIo("process I/O unavailable");
                try self.flushOutputForChild();
                const argv = shellArgv(command);
                var child = std.process.spawn(io, .{
                    .argv = &argv,
                    .environ_map = self.environmentMap(),
                }) catch return self.fail("process execution failed");
                const term = child.wait(io) catch {
                    child.kill(io);
                    return self.fail("process execution failed");
                };
                return processResult(term);
            },
        };
    }

    /// Read mode (`input == null`) returns the command's stdout; write mode feeds
    /// `input` to its stdin. Other streams are inherited, like C `popen`.
    pub fn popenProcess(self: *State, command: []const u8, input: ?[]const u8) !host.PopenResult {
        switch (self.options.process) {
            .disabled => return self.fail("'popen' not supported"),
            .custom => |process| {
                const popen = process.popen orelse return self.fail("'popen' not supported");
                const result = popen(process.context, self.allocator, command, input) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.fail("process execution failed");
                };
                if (result.output.len > self.options.max_file_bytes) {
                    self.allocator.free(result.output);
                    return self.fail("process output too large");
                }
                return result;
            },
            .enabled => if (comptime builtin.os.tag == .freestanding) {
                return self.fail("'popen' not supported");
            } else {
                const io = try self.requireIo("process I/O unavailable");
                try self.flushOutputForChild();
                const argv = shellArgv(command);
                var child = std.process.spawn(io, .{
                    .argv = &argv,
                    .environ_map = self.environmentMap(),
                    .stdin = if (input == null) .inherit else .pipe,
                    .stdout = if (input == null) .pipe else .inherit,
                }) catch return self.fail("process execution failed");
                var output: []const u8 = "";
                errdefer self.allocator.free(output);
                if (input) |bytes| {
                    const stdin = child.stdin.?;
                    stdin.writeStreamingAll(io, bytes) catch {};
                    stdin.close(io);
                    child.stdin = null;
                } else {
                    var buffer: [4096]u8 = undefined;
                    var reader = child.stdout.?.readerStreaming(io, &buffer);
                    output = reader.interface.allocRemaining(self.allocator, .limited(self.options.max_file_bytes)) catch |err| {
                        child.kill(io);
                        if (err == error.OutOfMemory) return error.OutOfMemory;
                        return self.fail(if (err == error.StreamTooLong) "process output too large" else "process execution failed");
                    };
                }
                const term = child.wait(io) catch {
                    child.kill(io);
                    return self.fail("process execution failed");
                };
                return .{ .output = output, .result = processResult(term) };
            },
        }
    }

    /// The caller then unwinds with `error.LuaExit`.
    pub fn requestExit(self: *State, code: i32, close: bool) !void {
        switch (self.options.process) {
            .disabled => return self.fail("process access disabled"),
            .enabled => {},
            .custom => |process| if (process.exit) |exit| exit(process.context, code, close) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.fail("process exit failed");
            },
        }
        self.flushStdout() catch {};
        self.flushStderr() catch {};
        self.exit_request = .{ .code = code, .close = close };
    }

    fn finishExitUnwind(self: *State, thread: *Thread) !void {
        const request = self.exit_request orelse return;
        if (!request.close) return;
        self.closeFramesTo(thread, 0, null) catch |err| if (err == error.OutOfMemory) return err;
    }

    fn flushOutputForChild(self: *State) !void {
        try self.flushStdout();
        try self.flushStderr();
    }

    fn shellArgv(command: []const u8) [3][]const u8 {
        return if (comptime builtin.os.tag == .windows)
            .{ "cmd.exe", "/c", command }
        else
            .{ "/bin/sh", "-c", command };
    }

    fn processResult(term: std.process.Child.Term) ProcessResult {
        return switch (term) {
            .exited => |code| .{ .status = .exit, .code = code },
            .signal, .stopped => |signal| .{ .status = .signal, .code = signalNumber(signal) },
            .unknown => |code| .{ .status = .exit, .code = code },
        };
    }

    fn signalNumber(signal: anytype) i64 {
        return switch (@typeInfo(@TypeOf(signal))) {
            .@"enum" => @intCast(@intFromEnum(signal)),
            .int => @intCast(signal),
            else => 0,
        };
    }

    fn environmentMap(self: *State) ?*const std.process.Environ.Map {
        return switch (self.options.environment) {
            .map => |environment| environment,
            .disabled, .custom => null,
        };
    }

    pub fn requireIo(self: *State, unavailable_message: []const u8) RuntimeError!std.Io {
        return self.options.io orelse self.fail(unavailable_message);
    }

    pub fn processEnabled(self: *State) bool {
        return switch (self.options.process) {
            .disabled => false,
            .enabled, .custom => true,
        };
    }

    /// Reads the host `stdin_reader`, or the `stdin` bytes from `stdin_pos`.
    pub const StdinSource = struct {
        state: *State,
        fixed: std.Io.Reader,
        host: ?*std.Io.Reader,

        pub fn reader(self: *StdinSource) *std.Io.Reader {
            return self.host orelse &self.fixed;
        }

        /// Records the memory bytes consumed through `reader`.
        pub fn finish(self: *StdinSource) void {
            if (self.host == null) self.state.stdin_pos += self.fixed.seek;
        }
    };

    /// Callers read through `reader()` and then call `finish()`.
    pub fn stdinSource(self: *State) StdinSource {
        if (self.options.stdin_reader) |reader| {
            self.flushStdoutForInput();
            return .{ .state = self, .fixed = .fixed(""), .host = reader };
        }
        const input = self.options.stdin;
        return .{ .state = self, .fixed = .fixed(input[@min(self.stdin_pos, input.len)..]), .host = null };
    }

    pub fn stdinIsStream(self: *const State) bool {
        return self.options.stdin_reader != null;
    }

    pub fn loadSourceAsClosure(self: *State, source: []const u8) !Value {
        return self.loadSourceAsClosureNamed(source, null);
    }

    pub fn loadSourceAsClosureNamed(self: *State, source: []const u8, source_name: ?[]const u8) !Value {
        return self.loadSourceAsClosureNamedEnv(source, source_name, self.defaultEnvironment());
    }

    pub fn loadSourceAsClosureNamedEnv(self: *State, source: []const u8, source_name: ?[]const u8, environment: Value) !Value {
        var diagnostic: ?errors.Diagnostic = null;
        var tree = frontend.parseWithDiagnostic(self.allocator, source, &diagnostic) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return self.failLoadDiagnostic(source_name, source, diagnostic, "cannot load source"),
        };
        defer tree.deinit();

        compile.resolver.resolveWithDiagnostic(self.allocator, &tree, &diagnostic) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return self.failLoadDiagnostic(source_name, source, diagnostic, "cannot resolve source"),
        };
        const proto = try self.allocator.create(proto_mod.Proto);
        errdefer self.allocator.destroy(proto);
        proto.* = compile.compileWithDiagnostic(self.allocator, &tree, &diagnostic) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return self.failLoadDiagnostic(source_name, source, diagnostic, "cannot compile source"),
        };
        errdefer proto.deinit();
        if (source_name) |name| try setProtoSourceName(proto, name);
        try value_mod.prepareProtoTree(proto);
        try self.registerAllocation("proto_allocations", proto);
        errdefer {
            const removed = self.proto_allocations.pop().?;
            if (self.rollback) |journal| journal.freed(@intFromPtr(removed));
        }
        return .{ .closure = try self.newRootClosureWithEnv(proto, environment) };
    }

    pub fn loadBinaryDump(self: *State, source: []const u8, environment: Value) !Value {
        var header = std.ArrayList(u8).empty;
        defer header.deinit(self.allocator);
        try appendBinaryChunkHeader(self.allocator, &header);

        if (source.len < header.items.len) return self.fail("truncated binary chunk");
        if (!std.mem.eql(u8, source[0..header.items.len], header.items)) return self.fail("bad binary chunk");

        var pos = header.items.len;
        if (source.len < pos + binary_chunk_payload_magic.len) return self.fail("truncated binary chunk");
        if (!std.mem.eql(u8, source[pos .. pos + binary_chunk_payload_magic.len], binary_chunk_payload_magic)) return self.fail("unsupported PUC Lua binary chunk");
        pos += binary_chunk_payload_magic.len;

        var reader = BinaryChunkReader{ .state = self, .source = source, .pos = pos };
        const stripped_debug = try reader.readBool();
        const proto = try reader.readProto(null);
        errdefer {
            proto.deinit();
            self.allocator.destroy(proto);
        }
        if (reader.pos != source.len) return self.fail("bad binary chunk");
        try value_mod.prepareProtoTree(proto);
        try self.registerAllocation("proto_allocations", proto);
        errdefer {
            _ = self.proto_allocations.pop();
            if (self.rollback) |journal| journal.freed(@intFromPtr(proto));
        }
        return self.newDumpedClosure(proto, environment, stripped_debug);
    }

    pub fn loadFileAsClosure(self: *State, path: []const u8) !Value {
        return self.loadFileAsClosureNamed(path, null);
    }

    pub fn loadFileAsClosureNamed(self: *State, path: []const u8, source_name: ?[]const u8) !Value {
        const source = try self.readFileAlloc(path);
        errdefer self.allocator.free(source);
        const allocated_source_name = if (source_name == null) try std.fmt.allocPrint(self.allocator, "@{s}", .{path}) else null;
        defer if (allocated_source_name) |name| self.allocator.free(name);
        const closure = try self.loadSourceAsClosureNamed(source, source_name orelse allocated_source_name.?);
        try self.registerAllocation("source_allocations", source);
        return closure;
    }

    fn setRootThreadArgs(self: *State, thread: *Thread, args: []const Value) !void {
        const proto = thread.frames.items[0].proto;
        const param_count = @min(args.len, proto.param_count);
        for (args[0..param_count], 0..) |arg, index| thread.stack.items[index] = arg;

        if (!proto.is_vararg or args.len <= proto.param_count) return;
        const owned_args = try self.allocator.dupe(Value, args[proto.param_count..]);
        thread.frames.items[0].varargs = owned_args;
        thread.frames.items[0].owns_varargs = true;
        thread.frame_storage_bytes += owned_args.len * @sizeOf(Value);
    }

    pub fn callCollect(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror![]Value {
        const frame_count = thread.frames.items.len;
        const relative_base = thread.scratchRegister();
        const base = thread.frames.items[frame_count - 1].base + @as(usize, relative_base);
        try thread.ensureStack(self.allocator, base + 1 + args.len, self.callStackValueLimit(thread));
        thread.stack.items[base] = callable;
        for (args, 0..) |arg, index| thread.stack.items[base + 1 + index] = arg;

        try self.invokeValue(thread, .{ .base = relative_base, .arg_count = @intCast(args.len), .return_count = bytecode.multret_count }, 0);
        try self.runThreadUntil(thread, frame_count);
        return self.copyStackSlice(thread, thread.last_result_base, thread.last_result_count);
    }

    fn loadConstant(self: *State, constant: bytecode.Constant) !Value {
        return switch (constant) {
            .nil => .nil,
            .boolean => |value| .{ .boolean = value },
            .integer => |lexeme| try parseIntegerLiteral(lexeme),
            .number => |lexeme| .{ .number = try parseLuaNumber(lexeme) },
            .string => |lexeme| .{ .string = try self.decodeStringLiteral(lexeme) },
        };
    }

    inline fn protoConstant(self: *State, closure: *Closure, proto: *const proto_mod.Proto, index: bytecode.ConstantIndex) !Value {
        if (index < proto.constant_values.len) {
            const decoded = proto.constant_values[index];
            if (decoded != .string) return decoded;
        }
        return self.closureConstant(closure, index);
    }

    fn closureConstant(self: *State, closure: *Closure, index: bytecode.ConstantIndex) !Value {
        if (closure.constants) |cache| if (cache[index]) |value| return value;
        try rollback_mod.closureWritable(closure);
        if (closure.constants == null) closure.constants = try self.allocateConstantCache(closure.proto);
        const constants = closure.constants.?;
        if (constants[index] == null) constants[index] = try self.loadConstant(closure.proto.constants.items[index]);
        self.writeBarrier(closure, constants[index].?);
        return constants[index].?;
    }

    fn allocateConstantCache(self: *State, proto: *const proto_mod.Proto) ![]?Value {
        const constants = try self.allocator.alloc(?Value, proto.constants.items.len);
        errdefer self.allocator.free(constants);
        @memset(constants, null);
        self.noteAllocation(constants.len * @sizeOf(?Value));
        return constants;
    }

    pub fn intern(self: *State, bytes: []const u8) ![]const u8 {
        if (stdlib_static_strings.canonical(bytes)) |static| return static;
        if (self.strings.get(bytes)) |interned| {
            // The registry holds strings weakly; reuse during sweeping must resurrect the string.
            if (self.gc_phase != .pause) self.markString(interned);
            return interned;
        }
        const interned = try self.allocateString(bytes);
        try self.strings.put(interned, interned);
        return interned;
    }

    pub fn allocateString(self: *State, bytes: []const u8) ![]const u8 {
        return self.adoptString(try self.allocator.dupe(u8, bytes));
    }

    fn adoptString(self: *State, allocated: []u8) ![]const u8 {
        errdefer self.allocator.free(allocated);
        try self.registerAllocation("string_allocations", StringAllocation{ .bytes = allocated });
        errdefer {
            const removed = self.string_allocations.pop().?;
            if (self.rollback) |journal| journal.freed(@intFromPtr(removed.bytes.ptr));
        }
        if (allocated.len != 0) try self.string_allocation_index.put(@intFromPtr(allocated.ptr), self.string_allocations.items.len - 1);
        self.noteAllocation(@sizeOf(StringAllocation) + allocated.len);
        return allocated;
    }

    fn decodeStringLiteral(self: *State, lexeme: []const u8) ![]const u8 {
        if (lexeme.len < 2) return lexeme;
        if (lexeme[0] == '\'' or lexeme[0] == '"') return self.decodeShortString(lexeme);
        if (lexeme[0] == '[') return self.decodeLongString(lexeme);
        return lexeme;
    }

    fn decodeShortString(self: *State, lexeme: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.allocator);

        var index: usize = 1;
        while (index + 1 < lexeme.len) {
            const byte = lexeme[index];
            index += 1;
            if (byte != '\\') {
                try out.append(self.allocator, byte);
                continue;
            }
            if (index >= lexeme.len - 1) return self.fail("unfinished string escape");
            const escaped = lexeme[index];
            index += 1;
            switch (escaped) {
                'a' => try out.append(self.allocator, 0x07),
                'b' => try out.append(self.allocator, 0x08),
                'f' => try out.append(self.allocator, 0x0c),
                'n' => try out.append(self.allocator, '\n'),
                'r' => try out.append(self.allocator, '\r'),
                't' => try out.append(self.allocator, '\t'),
                'v' => try out.append(self.allocator, 0x0b),
                '\\', '"', '\'' => try out.append(self.allocator, escaped),
                'x' => {
                    if (index + 1 >= lexeme.len) return self.fail("invalid hexadecimal escape");
                    const value = hexValue(lexeme[index]) * 16 + hexValue(lexeme[index + 1]);
                    index += 2;
                    try out.append(self.allocator, @intCast(value));
                },
                '0'...'9' => {
                    var value: u32 = escaped - '0';
                    var count: usize = 1;
                    while (count < 3 and index < lexeme.len - 1 and std.ascii.isDigit(lexeme[index])) : (count += 1) {
                        value = value * 10 + lexeme[index] - '0';
                        index += 1;
                    }
                    if (value > 255) return self.fail("decimal escape too large");
                    try out.append(self.allocator, @intCast(value));
                },
                'z' => while (index < lexeme.len - 1 and std.ascii.isWhitespace(lexeme[index])) : (index += 1) {},
                'u' => {
                    if (index >= lexeme.len - 1 or lexeme[index] != '{') return self.fail("invalid unicode escape");
                    index += 1;
                    var value: u32 = 0;
                    var count: usize = 0;
                    while (index < lexeme.len - 1 and lexeme[index] != '}') : (index += 1) {
                        value = appendUnicodeEscapeDigit(value, hexValue(lexeme[index]));
                        count += 1;
                    }
                    if (count == 0 or index >= lexeme.len - 1 or lexeme[index] != '}' or value > max_lua_utf8_codepoint) return self.fail("invalid unicode escape");
                    index += 1;
                    var encoded: [6]u8 = undefined;
                    const len = encodeLuaUtf8(value, &encoded) orelse return self.fail("invalid unicode escape");
                    try out.appendSlice(self.allocator, encoded[0..len]);
                },
                '\n' => {
                    if (index < lexeme.len - 1 and lexeme[index] == '\r') index += 1;
                    try out.append(self.allocator, '\n');
                },
                '\r' => {
                    if (index < lexeme.len - 1 and lexeme[index] == '\n') index += 1;
                    try out.append(self.allocator, '\n');
                },
                else => return self.fail("invalid string escape"),
            }
        }

        const bytes = try self.intern(out.items);
        out.deinit(self.allocator);
        return bytes;
    }

    fn decodeLongString(self: *State, lexeme: []const u8) ![]const u8 {
        var level: usize = 0;
        while (1 + level < lexeme.len and lexeme[1 + level] == '=') level += 1;
        const content_start = level + 2;
        const content_end = lexeme.len - level - 2;
        var content = lexeme[content_start..content_end];
        if (std.mem.startsWith(u8, content, "\r\n") or std.mem.startsWith(u8, content, "\n\r")) {
            content = content[2..];
        } else if (std.mem.startsWith(u8, content, "\n") or std.mem.startsWith(u8, content, "\r")) {
            content = content[1..];
        }
        if (std.mem.indexOfScalar(u8, content, '\r')) |_| {
            const normalized = try self.normalizeLongStringLineEnds(content);
            defer self.allocator.free(normalized);
            return self.intern(normalized);
        }
        return self.intern(content);
    }

    fn normalizeLongStringLineEnds(self: *State, content: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.allocator);
        var index: usize = 0;
        while (index < content.len) {
            const byte = content[index];
            if (byte == '\r') {
                try out.append(self.allocator, '\n');
                index += if (index + 1 < content.len and content[index + 1] == '\n') 2 else 1;
            } else if (byte == '\n' and index + 1 < content.len and content[index + 1] == '\r') {
                try out.append(self.allocator, '\n');
                index += 2;
            } else {
                try out.append(self.allocator, byte);
                index += 1;
            }
        }
        return out.toOwnedSlice(self.allocator);
    }

    pub fn newTableWithHints(self: *State, array_hint: u32, hash_hint: u32) !Value {
        const table = try self.allocator.create(Table);
        errdefer self.allocator.destroy(table);
        table.* = try Table.init(self.allocator, array_hint, hash_hint);
        errdefer table.deinit(self.allocator);
        try self.registerAllocation("table_allocations", table);
        errdefer {
            const removed = self.table_allocations.pop().?;
            if (self.rollback) |journal| journal.freed(@intFromPtr(removed));
        }
        try self.table_allocation_index.put(@intFromPtr(table), self.table_allocations.items.len - 1);
        self.noteAllocation(tableGcBytes(table));
        return .{ .table = table };
    }

    pub fn newUserdata(self: *State, ptr: *anyopaque, type_id: usize, type_name: []const u8, finalizer: ?UserdataFinalizer, finalizer_data: ?*const anyopaque, deinit_fn: ?UserdataDeinit) !Value {
        const userdata = try self.allocator.create(Userdata);
        errdefer self.allocator.destroy(userdata);
        userdata.* = .{
            .ptr = ptr,
            .type_id = type_id,
            .type_name = type_name,
            .finalizer = finalizer,
            .finalizer_data = finalizer_data,
            .deinit_fn = deinit_fn,
        };
        const payload = try self.allocator.create(types.UserdataPayload);
        errdefer self.allocator.destroy(payload);
        payload.* = .{ .allocator = self.allocator, .lifetime = self.allocator_lifetime, .ptr = ptr, .finalizer = finalizer, .finalizer_data = finalizer_data, .dispose = deinit_fn };
        try self.registerAllocation("userdata_allocations", userdata);
        if (payload.lifetime) |l| l.retain();
        userdata.payload = payload;
        self.noteAllocation(gc_mod.userdataBytes(userdata));
        return .{ .userdata = userdata };
    }

    fn newRootClosure(self: *State, proto: *const proto_mod.Proto) !*Closure {
        return self.newRootClosureWithEnv(proto, self.defaultEnvironment());
    }

    fn newRootClosureWithEnv(self: *State, proto: *const proto_mod.Proto, environment: Value) !*Closure {
        var upvalues: []*Upvalue = if (proto.upvalues.items.len == 0)
            &.{}
        else
            try self.allocator.alloc(*Upvalue, proto.upvalues.items.len);
        errdefer if (upvalues.len != 0) self.allocator.free(upvalues);

        for (proto.upvalues.items, 0..) |desc, index| {
            const upvalue = try self.allocator.create(Upvalue);
            errdefer self.allocator.destroy(upvalue);
            upvalue.* = .{
                .owner = undefined,
                .stack_index = 0,
                .closed = if (std.mem.eql(u8, desc.name, "_ENV")) environment else .nil,
                .is_open = false,
            };
            try self.registerAllocation("upvalue_allocations", upvalue);
            self.noteAllocation(@sizeOf(Upvalue));
            upvalues[index] = upvalue;
        }

        const closure = try self.allocator.create(Closure);
        errdefer self.allocator.destroy(closure);
        assertProtoPrepared(proto);
        closure.* = .{ .proto = proto, .upvalues = upvalues };
        try self.registerAllocation("closure_allocations", closure);
        self.noteAllocation(@sizeOf(Closure));
        return closure;
    }

    fn defaultEnvironment(self: *State) Value {
        return if (self.global_table) |table| .{ .table = table } else self.getGlobalValue("_G");
    }

    fn newDumpedClosure(self: *State, proto: *const proto_mod.Proto, environment: Value, stripped_debug: bool) !Value {
        var upvalues: []*Upvalue = if (proto.upvalues.items.len == 0)
            &.{}
        else
            try self.allocator.alloc(*Upvalue, proto.upvalues.items.len);
        errdefer if (upvalues.len != 0) self.allocator.free(upvalues);

        for (proto.upvalues.items, 0..) |desc, index| {
            const upvalue = try self.allocator.create(Upvalue);
            errdefer self.allocator.destroy(upvalue);
            upvalue.* = .{
                .owner = undefined,
                .stack_index = 0,
                .closed = if (std.mem.eql(u8, desc.name, "_ENV")) environment else .nil,
                .is_open = false,
            };
            try self.registerAllocation("upvalue_allocations", upvalue);
            self.noteAllocation(@sizeOf(Upvalue));
            upvalues[index] = upvalue;
        }

        const closure = try self.allocator.create(Closure);
        assertProtoPrepared(proto);
        closure.* = .{ .proto = proto, .upvalues = upvalues, .stripped_debug = stripped_debug };
        errdefer self.allocator.destroy(closure);
        try self.registerAllocation("closure_allocations", closure);
        self.noteAllocation(@sizeOf(Closure));
        return .{ .closure = closure };
    }

    fn newClosure(self: *State, thread: *Thread, proto: *const proto_mod.Proto) !Value {
        const parent = thread.frames.items[thread.frames.items.len - 1];
        const upvalues = try self.allocator.alloc(*Upvalue, proto.upvalues.items.len);
        errdefer self.allocator.free(upvalues);
        for (proto.upvalues.items, 0..) |desc, index| {
            upvalues[index] = if (desc.in_stack)
                try self.captureUpvalue(thread, parent.base + desc.index)
            else
                parent.closure.upvalues[desc.index];
        }

        const closure = try self.allocator.create(Closure);
        assertProtoPrepared(proto);
        closure.* = .{ .proto = proto, .upvalues = upvalues, .stripped_debug = parent.closure.stripped_debug };
        errdefer self.allocator.destroy(closure);
        try self.registerAllocation("closure_allocations", closure);
        self.noteAllocation(@sizeOf(Closure));
        return .{ .closure = closure };
    }

    fn captureUpvalue(self: *State, thread: *Thread, stack_index: usize) !*Upvalue {
        var previous: ?*Upvalue = null;
        var current = thread.open_upvalues;
        while (current) |upvalue| : (current = upvalue.next) {
            if (upvalue.stack_index <= stack_index) {
                if (upvalue.stack_index == stack_index) return upvalue;
                break;
            }
            previous = upvalue;
        }

        const upvalue = try self.allocator.create(Upvalue);
        errdefer self.allocator.destroy(upvalue);
        upvalue.* = .{ .owner = thread, .stack_index = stack_index, .next = current };
        try self.registerAllocation("upvalue_allocations", upvalue);
        self.noteAllocation(@sizeOf(Upvalue));
        if (previous) |prev| {
            rollback_mod.touch(prev);
            prev.next = upvalue;
        } else {
            thread.open_upvalues = upvalue;
        }
        return upvalue;
    }

    fn readUpvalue(self: *State, thread: *Thread, index: bytecode.UpvalueIndex) Value {
        _ = self;
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const upvalue = frame.closure.upvalues[index];
        return if (upvalue.is_open) upvalue.owner.stack.items[upvalue.stack_index] else upvalue.closed;
    }

    fn writeUpvalue(self: *State, thread: *Thread, index: bytecode.UpvalueIndex, value: Value) !void {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const upvalue = frame.closure.upvalues[index];
        rollback_mod.touch(upvalue);
        if (upvalue.is_open) {
            try rollback_mod.threadWritable(upvalue.owner);
            upvalue.owner.stack.items[upvalue.stack_index] = value;
            self.threadBarrier(upvalue.owner, value);
        } else {
            upvalue.closed = value;
            self.writeBarrier(upvalue, value);
        }
    }

    pub fn closeUpvalues(self: *State, thread: *Thread, first_stack_index: usize) void {
        while (thread.open_upvalues) |upvalue| {
            if (upvalue.stack_index < first_stack_index) break;
            std.debug.assert(upvalue.is_open);
            rollback_mod.touch(upvalue);
            rollback_mod.touch(thread);
            upvalue.closed = thread.stack.items[upvalue.stack_index];
            self.writeBarrier(upvalue, upvalue.closed);
            upvalue.is_open = false;
            thread.open_upvalues = upvalue.next;
            upvalue.next = null;
        }
    }

    fn checkToBeClosedRegister(self: *State, thread: *Thread, register: bytecode.Register) !void {
        const value = self.get(thread, register);
        if (value == .nil) return;
        if (value == .boolean and !value.boolean) return;
        if ((try self.getMetaEvent(value, .__close)) == null) {
            const frame = thread.frames.items[thread.frames.items.len - 1];
            thread.stack.items[frame.base + register] = .nil;
            if (self.toBeClosedLocalName(thread, register)) |name| {
                const message = try std.fmt.allocPrint(self.allocator, "variable '{s}' got a non-closable value", .{name});
                defer self.allocator.free(message);
                return self.failRuntimeDetail(thread, message);
            }
            return self.failRuntimeDetail(thread, "variable got a non-closable value");
        }
    }

    fn toBeClosedLocalName(self: *State, thread: *Thread, register: bytecode.Register) ?[]const u8 {
        _ = self;
        const frame = thread.frames.items[thread.frames.items.len - 1];
        for (frame.proto.locals.items) |local| {
            if (!local.to_close or local.register != register) continue;
            if (!localActiveAt(local, frame.pc)) continue;
            return local.name;
        }
        return null;
    }

    fn closeToBeClosedRegister(self: *State, thread: *Thread, register: bytecode.Register, error_value: ?Value) anyerror!void {
        const frame_count = thread.frames.items.len;
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const absolute_register = frame.base + register;
        const value = thread.stack.items[absolute_register];
        if (value == .nil) return;
        if (value == .boolean and !value.boolean) return;
        const metamethod = (try self.getMetaEvent(value, .__close)) orelse {
            thread.stack.items[absolute_register] = .nil;
            return self.fail("metamethod 'close'");
        };
        _ = (if (error_value) |err_value|
            call_mod.callOneNamed(State, self, thread, "close", "metamethod", metamethod, &.{ value, try self.caughtErrorValue(err_value) })
        else
            call_mod.callOneNamed(State, self, thread, "close", "metamethod", metamethod, &.{value})) catch |err| {
            if (err == error.CoroutineYield and error_value != null) {
                thread.pending_unwind_error = error_value.?;
                self.threadBarrier(thread, error_value.?);
                thread.pending_unwind_resume_frame_count = frame_count;
                thread.pending_unwind_target_frame_count = if (frame_count == 0) 0 else frame_count - 1;
            }
            if (isRuntimeError(err)) {
                var close_err = err;
                self.noteCaughtError(err);
                try self.applyMessageHandler(thread);
                self.closeFramesTo(thread, frame_count, self.currentErrorValue()) catch |unwind_err| {
                    close_err = unwind_err;
                    if (!isRuntimeError(unwind_err)) return unwind_err;
                };
                thread.stack.items[absolute_register] = .nil;
                return close_err;
            }
            thread.stack.items[absolute_register] = .nil;
            return err;
        };
        thread.stack.items[absolute_register] = .nil;
    }

    fn jumpThread(self: *State, thread: *Thread, offset: bytecode.JumpOffset, auto_gc: bool) !void {
        const frame_index = thread.frames.items.len - 1;
        const frame = &thread.frames.items[frame_index];
        const source_pc = frame.pc;
        const target_pc = jumpTarget(source_pc, offset);
        if (frame.proto.has_to_close_locals) try self.closeToBeClosedExitingPc(thread, frame_index, source_pc, target_pc, null);
        thread.frames.items[frame_index].pc = target_pc;
        if (target_pc < source_pc) {
            thread.frames.items[frame_index].last_hook_line = null;
            if (auto_gc and self.gc_running and self.shouldRunAutoGc()) try gc_mod.autoStep(State, self, thread);
        }
    }

    fn jumpThreadMaybeFast(self: *State, thread: *Thread, offset: bytecode.JumpOffset, auto_gc: bool) !void {
        const frame = &thread.frames.items[thread.frames.items.len - 1];
        if (frame.proto.has_to_close_locals) return self.jumpThread(thread, offset, auto_gc);

        const source_pc = frame.pc;
        const target_pc = jumpTarget(source_pc, offset);
        frame.pc = target_pc;
        if (target_pc < source_pc) {
            frame.last_hook_line = null;
            if (auto_gc and self.gc_running and self.shouldRunAutoGc()) try gc_mod.autoStep(State, self, thread);
        }
    }

    fn forPrep(self: *State, thread: *Thread, op: bytecode.ForLoop) !void {
        const initial = self.get(thread, op.base);
        const limit = self.get(thread, op.base + 1);
        const step = self.get(thread, op.base + 2);
        if (toInteger(initial)) |initial_integer| {
            if (toInteger(step)) |step_integer| {
                if (step_integer == 0) return self.failRuntimeDetail(thread, "'for' step is zero");
                const limit_integer = toInteger(limit) orelse blk: {
                    const limit_number = toNumberMaybe(limit) orelse return self.failForTypeError(thread, .limit, limit);
                    break :blk integerForLimit(limit_number, step_integer) orelse {
                        self.set(thread, op.base, .{ .integer = initial_integer });
                        self.set(thread, op.base + 1, .{ .integer = initial_integer });
                        self.set(thread, op.base + 2, .{ .integer = step_integer });
                        try self.jumpThread(thread, op.offset, false);
                        return;
                    };
                };
                self.set(thread, op.base, .{ .integer = initial_integer });
                self.set(thread, op.base + 1, .{ .integer = limit_integer });
                self.set(thread, op.base + 2, .{ .integer = step_integer });
                if (!forLoopContinuesInteger(initial_integer, limit_integer, step_integer)) try self.jumpThread(thread, op.offset, false);
                return;
            }
        }

        const initial_number = toNumberMaybe(initial) orelse return self.failForTypeError(thread, .initial, initial);
        const limit_number = toNumberMaybe(limit) orelse return self.failForTypeError(thread, .limit, limit);
        const step_number = toNumberMaybe(step) orelse return self.failForTypeError(thread, .step, step);
        if (step_number == 0) return self.failRuntimeDetail(thread, "'for' step is zero");
        self.set(thread, op.base, .{ .number = initial_number });
        self.set(thread, op.base + 1, .{ .number = limit_number });
        self.set(thread, op.base + 2, .{ .number = step_number });
        if (!forLoopContinuesNumber(initial_number, limit_number, step_number)) try self.jumpThread(thread, op.offset, false);
    }

    fn forLoop(self: *State, thread: *Thread, op: bytecode.ForLoop) !void {
        const frame = &thread.frames.items[thread.frames.items.len - 1];
        const absolute_base = frame.base + op.base;
        const stack = thread.stack.items;
        const current = stack[absolute_base];
        const limit = stack[absolute_base + 1];
        const step = stack[absolute_base + 2];
        if (current == .integer and limit == .integer and step == .integer) {
            const next = current.integer +% step.integer;
            stack[absolute_base] = .{ .integer = next };
            const wrapped = (step.integer > 0 and next < current.integer) or (step.integer < 0 and next > current.integer);
            if (!wrapped and forLoopContinuesInteger(next, limit.integer, step.integer)) {
                if (frame.proto.has_to_close_locals) {
                    try self.jumpThread(thread, op.offset, false);
                } else {
                    const source_pc = frame.pc;
                    const target_pc = jumpTarget(source_pc, op.offset);
                    frame.pc = target_pc;
                    if (target_pc < source_pc) frame.last_hook_line = null;
                }
            }
            return;
        }

        const next = (try toNumber(current)) + (try toNumber(step));
        stack[absolute_base] = .{ .number = next };
        if (forLoopContinuesNumber(next, try toNumber(limit), try toNumber(step))) {
            if (frame.proto.has_to_close_locals) {
                try self.jumpThread(thread, op.offset, false);
            } else {
                const source_pc = frame.pc;
                const target_pc = jumpTarget(source_pc, op.offset);
                frame.pc = target_pc;
                if (target_pc < source_pc) frame.last_hook_line = null;
            }
        }
    }

    fn closeToBeClosedExitingPc(self: *State, thread: *Thread, frame_index: usize, source_pc: usize, target_pc: usize, error_value: ?Value) !void {
        const frame = thread.frames.items[frame_index];
        var pending_error = error_value;
        var close_failed = false;

        var index = frame.proto.locals.items.len;
        while (index > 0) {
            index -= 1;
            const local = frame.proto.locals.items[index];
            if (!local.to_close) continue;
            if (!localActiveAt(local, source_pc) or localActiveAt(local, target_pc)) continue;
            const value = thread.stack.items[frame.base + local.register];
            if (value != .nil and !(value == .boolean and !value.boolean) and (try self.getMetaEvent(value, .__close)) == null) continue;

            self.closeToBeClosedRegister(thread, local.register, pending_error) catch |err| {
                if (isRuntimeError(err)) {
                    self.discardFramesTo(thread, frame_index + 1);
                    pending_error = self.currentErrorValue();
                    close_failed = true;
                } else return err;
            };
        }

        if (close_failed) return self.rethrowValue(pending_error.?);
    }

    fn closeActiveToBeClosedInTopFrame(self: *State, thread: *Thread, error_value: ?Value) !void {
        const frame_index = thread.frames.items.len - 1;
        const frame = thread.frames.items[frame_index];
        if (frame.pc == 0) return;
        const pc = frame.pc - 1;
        var pending_error = error_value;
        var close_failed = false;

        var index = frame.proto.locals.items.len;
        while (index > 0) {
            index -= 1;
            const local = frame.proto.locals.items[index];
            if (!local.to_close or !localActiveAt(local, pc)) continue;

            self.closeToBeClosedRegister(thread, local.register, pending_error) catch |err| {
                if (isRuntimeError(err)) {
                    self.discardFramesTo(thread, frame_index + 1);
                    pending_error = self.currentErrorValue();
                    close_failed = true;
                } else return err;
            };
        }

        if (close_failed) return self.rethrowValue(pending_error.?);
    }

    pub fn closeFramesTo(self: *State, thread: *Thread, frame_count: usize, error_value: ?Value) !void {
        if (thread.frames.items.len > frame_count) abandonFramesAbove(thread, frame_count);
        var pending_error = error_value;
        var close_failed = false;
        const previous_native_call = thread.native_call;
        defer thread.native_call = previous_native_call;
        while (thread.frames.items.len > frame_count) {
            thread.native_call = runtimeNativeCall(thread);
            self.closeActiveToBeClosedInTopFrame(thread, pending_error) catch |err| {
                pending_error = self.currentErrorValue();
                close_failed = close_failed or isRuntimeError(err);
                if (!isRuntimeError(err)) return err;
            };
            const frame = thread.frames.items[thread.frames.items.len - 1];
            self.closeUpvalues(thread, frame.base);
            thread.releaseFrame(&thread.frames.items[thread.frames.items.len - 1], self.allocator);
            thread.frames.items.len -= 1;
        }
        if (close_failed) return self.rethrowValue(pending_error.?);
    }

    fn discardFramesTo(self: *State, thread: *Thread, frame_count: usize) void {
        if (thread.frames.items.len > frame_count) abandonFramesAbove(thread, frame_count);
        while (thread.frames.items.len > frame_count) {
            const frame = thread.frames.items[thread.frames.items.len - 1];
            self.closeUpvalues(thread, frame.base);
            thread.releaseFrame(&thread.frames.items[thread.frames.items.len - 1], self.allocator);
            thread.frames.items.len -= 1;
        }
    }

    /// Drops continuations and paused `__close` unwinds of frames above `frame_count`.
    fn abandonFramesAbove(thread: *Thread, frame_count: usize) void {
        if (thread.pending_unwind_resume_frame_count > frame_count) thread.pending_unwind_error = null;
        if (thread.continuation_frame_count <= frame_count) return;
        discardListAbove(&thread.pairs_continuations, frame_count);
        discardListAbove(&thread.call_one_continuations, frame_count);
        discardListAbove(&thread.protected_continuations, frame_count);
        discardListAbove(&thread.tail_call_continuations, frame_count);
        discardListAbove(&thread.generic_for_continuations, frame_count);
        thread.refreshContinuationFrameCount();
    }

    fn discardListAbove(list: anytype, frame_count: usize) void {
        var kept: usize = 0;
        for (list.items) |continuation| {
            const pending_frame_count = if (@hasField(@TypeOf(continuation), "context")) continuation.context.frame_count else continuation.frame_count;
            if (pending_frame_count > frame_count) continue;
            list.items[kept] = continuation;
            kept += 1;
        }
        list.items.len = kept;
    }

    fn getTable(self: *State, table_value: Value, key_value: Value) !Value {
        return self.getTableDepth(null, table_value, key_value, 0);
    }

    pub fn getTableValue(self: *State, table_value: Value, key_value: Value) !Value {
        return self.getTable(table_value, key_value);
    }

    pub fn getTableFromThread(self: *State, thread: *Thread, table_value: Value, key_value: Value) !Value {
        return self.getTableDepth(thread, table_value, key_value, 0);
    }

    fn getTableToRegister(self: *State, thread: *Thread, dest: bytecode.Register, table_value: Value, key_value: Value) !void {
        const value = try self.getTableDepthContinuable(thread, self.absoluteRegister(thread, dest), table_value, key_value, 0);
        self.set(thread, dest, value);
    }

    fn getTableDepthContinuable(self: *State, thread: *Thread, dest: usize, table_value: Value, key_value: Value, depth: usize) !Value {
        if (depth > max_metamethod_depth) return self.fail("'__index' chain too long");
        const key = try self.readableTableKey(key_value) orelse return .nil;

        if (table_value == .table) {
            const value = table_value.table.get(key);
            if (value != .nil) return value;
        }

        const metamethod = try self.getMetaEvent(table_value, .__index) orelse {
            if (table_value == .table) return .nil;
            return self.failIndexTypeError(thread, table_value);
        };

        return switch (metamethod) {
            .table => self.getTableDepthContinuable(thread, dest, metamethod, key, depth + 1),
            else => if (functionLike(metamethod))
                try self.callOneMetamethodWithContinuation(thread, "__index", metamethod, &.{ table_value, key }, .{ .value = dest })
            else
                self.failRuntimeDetail(thread, indexErrorMessage(metamethod)),
        };
    }

    fn getTableDepth(self: *State, thread: ?*Thread, table_value: Value, key_value: Value, depth: usize) !Value {
        if (depth > max_metamethod_depth) return self.fail("'__index' chain too long");
        const key = try self.readableTableKey(key_value) orelse return .nil;

        if (table_value == .table) {
            const value = table_value.table.get(key);
            if (value != .nil) return value;
        }

        const metamethod = try self.getMetaEvent(table_value, .__index) orelse {
            if (table_value == .table) return .nil;
            return self.failIndexTypeError(thread, table_value);
        };

        return switch (metamethod) {
            .table => self.getTableDepth(thread, metamethod, key, depth + 1),
            else => if (!functionLike(metamethod))
                self.failRuntimeDetail(thread, indexErrorMessage(metamethod))
            else if (thread) |active_thread|
                try self.callOneMetamethod(active_thread, "__index", metamethod, &.{ table_value, key })
            else
                self.fail(callErrorMessage(metamethod)),
        };
    }

    fn rawGet(self: *State, table_value: Value, key_value: Value) !Value {
        const table = switch (table_value) {
            .table => |table| table,
            else => return self.fail(indexErrorMessage(table_value)),
        };
        const key = try self.readableTableKey(key_value) orelse return .nil;
        return table.get(key);
    }

    fn setTable(self: *State, table_value: Value, key_value: Value, value: Value) !void {
        try self.setTableDepth(null, table_value, key_value, value, 0);
    }

    pub fn setTableValue(self: *State, table_value: Value, key_value: Value, value: Value) !void {
        try self.setTable(table_value, key_value, value);
    }

    pub fn setTableFromThread(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value) !void {
        try self.setTableDepth(thread, table_value, key_value, value, 0);
    }

    fn setTableFromThreadContinuable(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value) !void {
        try self.setTableDepthContinuable(thread, table_value, key_value, value, 0);
    }

    fn setTableDepthContinuable(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value, depth: usize) !void {
        if (depth > max_metamethod_depth) return self.fail("'__newindex' chain too long");
        const key = try self.writableTableKey(key_value);

        if (table_value == .table) {
            const table = table_value.table;
            if (table.rollback != null and table.get(key) != .nil) {
                try rollback_mod.tableWritable(table);
                self.noteTableCapacityDelta(table, 0);
            }
            if (table.setExistingNonNil(key, value)) {
                self.writeTableBarrier(table, key, value);
                return;
            }
        }

        const metamethod = try self.getMetaEvent(table_value, .__newindex) orelse {
            if (table_value == .table) {
                try self.setTableRaw(table_value.table, key, value);
                self.writeTableBarrier(table_value.table, key, value);
                return;
            }
            return self.failNewIndexTypeError(thread, table_value);
        };

        switch (metamethod) {
            .table => try self.setTableDepthContinuable(thread, metamethod, key, value, depth + 1),
            else => if (functionLike(metamethod)) {
                _ = try self.callOneMetamethodWithContinuation(thread, "__newindex", metamethod, &.{ table_value, key, value }, .discard);
            } else {
                return self.failRuntimeDetail(thread, indexErrorMessage(metamethod));
            },
        }
    }

    fn setTableDepth(self: *State, thread: ?*Thread, table_value: Value, key_value: Value, value: Value, depth: usize) !void {
        if (depth > max_metamethod_depth) return self.fail("'__newindex' chain too long");
        const key = try self.writableTableKey(key_value);

        if (table_value == .table) {
            const table = table_value.table;
            if (table.rollback != null and table.get(key) != .nil) {
                try rollback_mod.tableWritable(table);
                self.noteTableCapacityDelta(table, 0);
            }
            if (table.setExistingNonNil(key, value)) {
                self.writeTableBarrier(table, key, value);
                return;
            }
        }

        const metamethod = try self.getMetaEvent(table_value, .__newindex) orelse {
            if (table_value == .table) {
                try self.setTableRaw(table_value.table, key, value);
                self.writeTableBarrier(table_value.table, key, value);
                return;
            }
            return self.failNewIndexTypeError(thread, table_value);
        };

        switch (metamethod) {
            .table => try self.setTableDepth(thread, metamethod, key, value, depth + 1),
            else => if (!functionLike(metamethod)) {
                return self.failRuntimeDetail(thread, indexErrorMessage(metamethod));
            } else if (thread) |active_thread| {
                _ = try self.callOneMetamethod(active_thread, "__newindex", metamethod, &.{ table_value, key, value });
            } else {
                return self.fail(callErrorMessage(metamethod));
            },
        }
    }

    fn readableTableKey(self: *State, value: Value) !?Value {
        _ = self;
        return switch (value) {
            .nil => null,
            .number => |number| if (std.math.isNan(number)) null else if (floatToInteger(number)) |integer| .{ .integer = integer } else value,
            else => value,
        };
    }

    fn writableTableKey(self: *State, value: Value) !Value {
        return switch (value) {
            .nil => self.fail("table index is nil"),
            .number => |number| if (std.math.isNan(number)) self.fail("table index is NaN") else if (floatToInteger(number)) |integer| .{ .integer = integer } else value,
            else => value,
        };
    }

    pub fn lengthOf(self: *State, thread: *Thread, value: Value) !Value {
        return switch (value) {
            .string => |string| .{ .integer = @intCast(string.len) },
            .table => |table| if ((try self.getMetaEvent(value, .__len))) |metamethod|
                try self.callOneMetamethod(thread, "__len", metamethod, &.{ value, value })
            else
                .{ .integer = table.len() },
            else => if ((try self.getMetaEvent(value, .__len))) |metamethod|
                try self.callOneMetamethod(thread, "__len", metamethod, &.{ value, value })
            else
                self.failLengthTypeError(thread, value),
        };
    }

    /// Like `luaL_len`.
    pub fn lengthInteger(self: *State, thread: *Thread, value: Value) !i64 {
        return self.lengthToInteger(try self.lengthOf(thread, value));
    }

    pub fn lengthToInteger(self: *State, length: Value) !i64 {
        return value_mod.coerceToInteger(length) orelse self.failLibrary("object length is not an integer");
    }

    fn concatValues(self: *State, lhs: Value, rhs: Value) !Value {
        return self.concatStringValues(&.{ lhs, rhs });
    }

    fn concatStringValues(self: *State, values: []const Value) !Value {
        var scratch: [value_mod.max_number_text_len]u8 = undefined;
        var total: usize = 0;
        for (values) |value| total += switch (value) {
            .string => |string| string.len,
            else => value_mod.formatNumber(&scratch, value).len,
        };
        const bytes = try self.allocator.alloc(u8, total);
        var offset: usize = 0;
        for (values) |value| {
            const text = switch (value) {
                .string => |string| string,
                else => value_mod.formatNumber(&scratch, value),
            };
            @memcpy(bytes[offset..][0..text.len], text);
            offset += text.len;
        }
        return .{ .string = try self.adoptString(bytes) };
    }

    fn concatRangeToRegister(self: *State, thread: *Thread, op: bytecode.ConcatRange) !void {
        const base = thread.frames.items[thread.frames.items.len - 1].base;
        try self.finishConcatRange(thread, base + op.dest, base + op.first, op.count);
    }

    /// Like `luaV_concat`. Partial results stay in the operand slots so a yielding
    /// `__concat` can resume.
    pub fn finishConcatRange(self: *State, thread: *Thread, dest: usize, first: usize, count_in: usize) !void {
        var count = count_in;
        while (count > 1) {
            const operands = thread.stack.items[first .. first + count];
            var run: usize = 0;
            while (run < count and luaStringLike(operands[count - 1 - run])) run += 1;
            if (run >= 2) {
                const joined = try self.concatStringValues(operands[count - run ..]);
                thread.stack.items[first + count - run] = joined;
                count -= run - 1;
                continue;
            }
            const lhs = operands[count - 2];
            const rhs = operands[count - 1];
            const metamethod = (try self.getEitherMetamethod(lhs, rhs, "__concat")) orelse return self.failConcatRangeTypeError(thread, lhs, rhs, count - 2);
            const result = try self.callOneMetamethodWithContinuation(thread, "__concat", metamethod, &.{ lhs, rhs }, .{ .concat = .{ .dest = dest, .first = first, .count = count - 1 } });
            count -= 1;
            thread.stack.items[first + count - 1] = result;
        }
        thread.stack.items[dest] = thread.stack.items[first];
    }

    fn callValue(self: *State, thread: *Thread, op: bytecode.Call) !void {
        const resolved = try self.resolveCall(thread, op);
        const callee = self.get(thread, resolved.base);
        if (callee == .closure) {
            const call_name = thread.next_call_name;
            const call_namewhat = thread.next_call_namewhat;
            thread.next_call_name = null;
            thread.next_call_namewhat = null;
            try self.callClosure(thread, resolved, callee.closure, call_name, call_namewhat);
            return;
        }
        try self.invokeValue(thread, resolved, 0);
    }

    /// Native code the runtime runs on top of the current frame, such as error handling.
    fn runtimeNativeCall(thread: *Thread) types.NativeCall {
        return .{ .base = thread.scratchRegister(), .arg_count = 0, .frame_count = thread.frames.items.len, .from_native = false };
    }

    fn nativeCallInfo(thread: *Thread, resolved: bytecode.Call, outer: ?types.NativeCall, name: ?[]const u8, namewhat: ?[]const u8, extra_args: usize) types.NativeCall {
        const frame_count = thread.frames.items.len;
        return .{
            .base = resolved.base,
            .arg_count = resolved.arg_count,
            .extra_args = @intCast(extra_args),
            .frame_count = frame_count,
            .from_native = if (outer) |active| active.frame_count == frame_count else false,
            .outer_frame_count = if (outer) |active| active.frame_count else null,
            .name = name,
            .namewhat = namewhat,
        };
    }

    pub fn invokeValue(self: *State, thread: *Thread, resolved: bytecode.Call, depth: usize) anyerror!void {
        if (depth > max_metamethod_depth) return self.fail("'__call' chain too long");
        const callee = self.get(thread, resolved.base);
        if (callee == .coroutine_wrapper) {
            const previous_native_call = thread.native_call;
            defer thread.native_call = previous_native_call;
            thread.native_call = nativeCallInfo(thread, resolved, previous_native_call, null, null, depth);
            try self.callCoroutineWrapper(thread, resolved, callee.coroutine_wrapper);
            return;
        }

        const entering_native = isYieldBlockingNative(callee);
        if (entering_native) thread.native_call_depth += 1;
        defer {
            if (entering_native) thread.native_call_depth -= 1;
        }
        const call_name = thread.next_call_name;
        const call_namewhat = thread.next_call_namewhat;
        thread.next_call_name = null;
        thread.next_call_namewhat = null;
        const previous_native_call = thread.native_call;
        defer thread.native_call = previous_native_call;
        if (isNativeCallable(callee) or callee == .gmatch_iterator) {
            thread.native_call = nativeCallInfo(thread, resolved, previous_native_call, call_name, call_namewhat, depth);
        }
        const hook_native = isNativeCallable(callee) and !thread.hook_running;
        if (hook_native and thread.hook_call) {
            const previous_hook_func = thread.hook_level2_func;
            const previous_transfer_index_base = thread.hook_transfer_index_base;
            const previous_transfer_stack_base = thread.hook_transfer_stack_base;
            const previous_transfer_count = thread.hook_transfer_count;
            const previous_transfer_values = thread.hook_transfer_values;
            thread.hook_level2_func = callee;
            thread.hook_transfer_index_base = 1;
            thread.hook_transfer_stack_base = thread.frames.items[thread.frames.items.len - 1].base + resolved.base + 1;
            thread.hook_transfer_count = resolved.arg_count;
            thread.hook_transfer_values = &.{};
            defer {
                thread.hook_level2_func = previous_hook_func;
                thread.hook_transfer_index_base = previous_transfer_index_base;
                thread.hook_transfer_stack_base = previous_transfer_stack_base;
                thread.hook_transfer_count = previous_transfer_count;
                thread.hook_transfer_values = previous_transfer_values;
            }
            try self.callHook(thread, "call");
        }
        switch (callee) {
            .closure => |closure| try self.callClosure(thread, resolved, closure, call_name, call_namewhat),
            .api_callback => |id| try self.callApiCallbackDispatch(thread, resolved, id),
            .native_print => {
                for (0..resolved.arg_count) |index| {
                    if (index != 0) try self.writeStdout("\t");
                    const text = try self.valueToString(thread, argValue(self, thread, resolved, @intCast(index)));
                    try self.writeStdout(text);
                }
                try self.writeStdout("\n");
                try self.flushStdoutAfterPrint();
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{});
            },
            .native_tostring => {
                if (resolved.arg_count == 0) return self.failArgumentMessage("tostring", 1, "value expected");
                const value = self.get(thread, resolved.base + 1);
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{.{ .string = try self.valueToString(thread, value) }});
            },
            .native_getmetatable => {
                if (resolved.arg_count == 0) return self.failArgumentMessage("getmetatable", 1, "value expected");
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{try self.getMetatableValue(argValue(self, thread, resolved, 0))});
            },
            .native_setmetatable => {
                const table_value = argValue(self, thread, resolved, 0);
                if (table_value != .table) return self.failArgumentType("setmetatable", 1, "table", table_value);
                const metatable_value = argValue(self, thread, resolved, 1);
                if (metatable_value != .nil and metatable_value != .table) return self.failArgumentType("setmetatable", 2, "nil or table", metatable_value);
                try self.setMetatableValue(table_value, argValue(self, thread, resolved, 1));
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{table_value});
            },
            .native_rawequal => {
                if (resolved.arg_count < 2) return self.failArgumentMessage("rawequal", resolved.arg_count + 1, "value expected");
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{.{ .boolean = valuesEqual(argValue(self, thread, resolved, 0), argValue(self, thread, resolved, 1)) }});
            },
            .native_rawget => {
                _ = try self.expectArgumentTable(thread, resolved, "rawget", 0);
                if (resolved.arg_count < 2) return self.failArgumentMessage("rawget", 2, "value expected");
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{try self.rawGet(argValue(self, thread, resolved, 0), argValue(self, thread, resolved, 1))});
            },
            .native_rawset => {
                const table = argValue(self, thread, resolved, 0);
                _ = try self.expectArgumentTable(thread, resolved, "rawset", 0);
                if (resolved.arg_count < 3) return self.failArgumentMessage("rawset", @max(resolved.arg_count + 1, 2), "value expected");
                try self.rawSet(table, argValue(self, thread, resolved, 1), argValue(self, thread, resolved, 2));
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{table});
            },
            .native_rawlen => {
                const value = argValue(self, thread, resolved, 0);
                if (value != .string and value != .table) return self.failArgumentType("rawlen", 1, "table or string", value);
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{try self.rawLen(value)});
            },
            .native_next => {
                _ = try self.expectArgumentTable(thread, resolved, "next", 0);
                const values = try self.nextValues(argValue(self, thread, resolved, 0), argValue(self, thread, resolved, 1));
                const count: usize = if (values[0] == .nil) 1 else 2;
                try self.returnValues(thread, resolved.base, resolved.return_count, values[0..count]);
            },
            .native_pairs => {
                if (resolved.arg_count == 0) return self.failArgumentMessage("pairs", 1, "value expected");
                const value = argValue(self, thread, resolved, 0);
                if (try self.getMetaEvent(value, .__pairs)) |metamethod| {
                    thread.native_call_depth -= 1;
                    defer thread.native_call_depth += 1;
                    try self.callPairsMetamethod(thread, resolved, metamethod, value);
                    return;
                }
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{ .native_next, value, .nil, .nil });
            },
            .native_ipairs => {
                if (resolved.arg_count == 0) return self.failArgumentMessage("ipairs", 1, "value expected");
                const value = argValue(self, thread, resolved, 0);
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{ .native_ipairs_iter, value, .{ .integer = 0 } });
            },
            .native_ipairs_iter => {
                const values = try self.ipairsIterValues(thread, argValue(self, thread, resolved, 0), argValue(self, thread, resolved, 1));
                try self.returnValues(thread, resolved.base, resolved.return_count, values[0..if (values[0] == .nil) @as(usize, 1) else 2]);
            },
            .native_table_create => {
                const array_hint, const hash_hint = try self.tableCreateHints(thread, resolved);
                if (hash_hint > 1 << 30) return self.fail("table overflow");
                try self.returnValues(thread, resolved.base, resolved.return_count, &.{try self.newTableWithHints(array_hint, hash_hint)});
            },
            .native_select => try self.selectValues(thread, resolved),
            .native_assert => try self.assertValues(thread, resolved),
            .native_error => try self.errorValue(thread, resolved),
            .native_pcall => try self.pcallValues(thread, resolved),
            .native_xpcall => try self.xpcallValues(thread, resolved),
            .native_collectgarbage => try self.collectGarbageValue(thread, resolved),
            .native_debug_traceback => try self.tracebackValue(thread, resolved),
            .native_coroutine_create => try self.coroutineCreate(thread, resolved),
            .native_coroutine_resume => try self.coroutineResume(thread, resolved),
            .native_coroutine_yield => try self.coroutineYield(thread, resolved),
            .native_coroutine_status => try self.coroutineStatus(thread, resolved),
            .native_coroutine_running => try self.coroutineRunning(thread, resolved),
            .native_coroutine_isyieldable => try self.coroutineIsYieldable(thread, resolved),
            .native_coroutine_close => try self.coroutineClose(thread, resolved),
            .native_coroutine_wrap => try self.coroutineWrap(thread, resolved),
            .gmatch_iterator => |state_table| {
                if (state_table.get(.{ .string = "__zlua_lines_iterator" }) != .nil) {
                    const values = try stdlib.io.linesNext(self, .{ .table = state_table });
                    defer if (values.len != 0) self.allocator.free(values);
                    try self.returnValues(thread, resolved.base, resolved.return_count, values);
                } else if (state_table.get(.{ .string = "__zlua_fs_iterator" }) != .nil) {
                    const values = try stdlib.fs.iteratorNext(self, .{ .table = state_table });
                    defer if (values.len != 0) self.allocator.free(values);
                    try self.returnValues(thread, resolved.base, resolved.return_count, values);
                } else {
                    const values = try stdlib.string.gmatchNext(self, .{ .table = state_table });
                    try self.returnValues(thread, resolved.base, resolved.return_count, values.slice());
                }
            },
            .native => |native| try self.callNative(native, thread, resolved),
            else => {
                const metamethod = try self.getMetaEvent(callee, .__call) orelse return self.failCallTypeError(thread, callee, call_name, call_namewhat);
                try self.prependCallArgument(thread, resolved, metamethod, callee);
                thread.next_call_name = call_name;
                thread.next_call_namewhat = call_namewhat;
                try self.invokeValue(thread, .{ .base = resolved.base, .arg_count = resolved.arg_count + 1, .return_count = resolved.return_count }, depth + 1);
            },
        }
        if (hook_native and thread.hook_return) {
            const previous_hook_func = thread.hook_level2_func;
            const previous_transfer_index_base = thread.hook_transfer_index_base;
            const previous_transfer_stack_base = thread.hook_transfer_stack_base;
            const previous_transfer_count = thread.hook_transfer_count;
            const previous_transfer_values = thread.hook_transfer_values;
            thread.hook_level2_func = callee;
            thread.hook_transfer_index_base = 2;
            thread.hook_transfer_stack_base = thread.last_transfer_base;
            thread.hook_transfer_count = thread.last_transfer_count;
            thread.hook_transfer_values = &.{};
            defer {
                thread.hook_level2_func = previous_hook_func;
                thread.hook_transfer_index_base = previous_transfer_index_base;
                thread.hook_transfer_stack_base = previous_transfer_stack_base;
                thread.hook_transfer_count = previous_transfer_count;
                thread.hook_transfer_values = previous_transfer_values;
            }
            try self.callReturnHook(thread, call_name orelse nativeHookName(callee));
        }
    }

    fn prependCallArgument(self: *State, thread: *Thread, resolved: bytecode.Call, metamethod: Value, receiver: Value) !void {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const base = frame.base + resolved.base;
        try thread.ensureStack(self.allocator, base + 2 + resolved.arg_count, self.callStackValueLimit(thread));
        var index: usize = resolved.arg_count;
        while (index > 0) {
            index -= 1;
            thread.stack.items[base + 2 + index] = thread.stack.items[base + 1 + index];
        }
        thread.stack.items[base] = metamethod;
        thread.stack.items[base + 1] = receiver;
    }

    pub fn callOneResult(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!Value {
        return call_mod.callOneResult(State, self, thread, callable, args);
    }

    pub fn callOneResultWithContinuation(self: *State, thread: *Thread, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value {
        return call_mod.callOneResultWithContinuation(State, self, thread, callable, args, result);
    }

    pub fn callOneMetamethodWithContinuation(self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value {
        return call_mod.callOneMetamethodWithContinuation(State, self, thread, name, callable, args, result);
    }

    pub fn callOneMetamethod(self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value) anyerror!Value {
        return call_mod.callOneMetamethod(State, self, thread, name, callable, args);
    }

    pub fn metamethodDebugName(name: []const u8) []const u8 {
        return call_mod.metamethodDebugName(name);
    }

    pub fn callOneResultMaybeContinuation(self: *State, thread: *Thread, callable: Value, args: []const Value, continuation_result: ?CallOneContinuationResult) anyerror!Value {
        return call_mod.callOneResultMaybeContinuation(State, self, thread, callable, args, continuation_result);
    }

    pub fn pushCallOneContinuation(self: *State, thread: *Thread, frame_count: usize, result: CallOneContinuationResult) !void {
        return call_mod.pushCallOneContinuation(State, self, thread, frame_count, result);
    }

    pub fn readyCallOneContinuationIndex(thread: *Thread) ?usize {
        return call_mod.readyCallOneContinuationIndex(thread);
    }

    pub fn completeReadyCallOneContinuation(self: *State, thread: *Thread) !bool {
        return call_mod.completeReadyCallOneContinuation(State, self, thread);
    }

    pub fn protectedCall(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!ProtectedCallResult {
        return call_mod.protectedCall(State, self, thread, callable, args);
    }

    pub fn protectedCallContext(_: *State, thread: *Thread) ProtectedCallContext {
        return call_mod.protectedCallContext(State, undefined, thread);
    }

    pub fn protectedCallContextWithErrors(self: *State, thread: *Thread) ProtectedCallContext {
        return call_mod.protectedCallContextWithErrors(State, self, thread);
    }

    pub fn runProtectedCall(self: *State, thread: *Thread, context: ProtectedCallContext, callable: Value, args: []const Value) anyerror!ProtectedCallResult {
        return call_mod.runProtectedCall(State, self, thread, context, callable, args);
    }

    pub fn restoreProtectedCall(
        self: *State,
        thread: *Thread,
        context: ProtectedCallContext,
        error_value: Value,
    ) !Value {
        var failure = error_value;
        thread.protected_close_depth += 1;
        defer thread.protected_close_depth -= 1;
        self.closeFramesTo(thread, context.frame_count, error_value) catch |err| switch (err) {
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => failure = self.currentErrorValue(),
            else => return err,
        };
        thread.stack.items.len = context.stack_len;
        thread.last_result_base = context.last_result_base;
        thread.last_result_count = context.last_result_count;
        thread.error_handler = context.previous_error_handler;
        if (thread.frames.items.len < self.callFrameLimit() and context.stack_len < self.stackValueLimit()) thread.stack_error_space = false;
        self.last_error = context.last_error;
        return failure;
    }

    pub fn pushProtectedContinuation(self: *State, thread: *Thread, context: ProtectedCallContext, base: u32, return_count: u16) !void {
        return call_mod.pushProtectedContinuation(State, self, thread, context, base, return_count);
    }

    pub fn readyProtectedContinuationIndex(thread: *Thread) ?usize {
        return call_mod.readyProtectedContinuationIndex(thread);
    }

    pub fn errorProtectedContinuationIndex(thread: *Thread) ?usize {
        return call_mod.errorProtectedContinuationIndex(thread);
    }

    pub fn completeReadyProtectedContinuation(self: *State, thread: *Thread) !bool {
        return call_mod.completeReadyProtectedContinuation(State, self, thread);
    }

    pub fn completeProtectedContinuationError(self: *State, thread: *Thread) !bool {
        return call_mod.completeProtectedContinuationError(State, self, thread);
    }

    pub fn returnProtectedContinuationSuccess(self: *State, thread: *Thread, continuation: ProtectedContinuation, values: []Value) !void {
        return call_mod.returnProtectedContinuationSuccess(State, self, thread, continuation, values);
    }

    pub fn returnProtectedContinuationFailure(self: *State, thread: *Thread, continuation: ProtectedContinuation, failure: Value) !void {
        return call_mod.returnProtectedContinuationFailure(State, self, thread, continuation, failure);
    }

    pub fn valueToString(self: *State, thread: *Thread, value: Value) anyerror![]const u8 {
        if (try self.getMetaEvent(value, .__tostring)) |metamethod| {
            const result = try self.callOneResult(thread, metamethod, &.{value});
            return switch (result) {
                .string => |string| string,
                .integer, .number => {
                    var buffer: [value_mod.max_number_text_len]u8 = undefined;
                    return self.intern(value_mod.formatNumber(&buffer, result));
                },
                else => self.failLibrary("'__tostring' must return a string"),
            };
        }

        if (try self.getMetaEvent(value, .__name)) |name| {
            if (name == .string) {
                var named = std.ArrayList(u8).empty;
                defer named.deinit(self.allocator);
                try appendNamedValue(self.allocator, &named, name.string, value);
                return self.intern(named.items);
            }
        }

        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        try value_mod.appendValue(self.allocator, &out, value);
        return self.intern(out.items);
    }

    /// Ignores `__metatable`, as `debug.getmetatable` does.
    pub fn rawMetatableValue(self: *State, value: Value) Value {
        const metatable = switch (value) {
            .table => |table| table.metatable,
            .userdata => |userdata| userdata.metatable,
            .string => self.string_metatable,
            .integer, .number => self.number_metatable,
            .boolean => self.boolean_metatable,
            .nil => self.nil_metatable,
            else => null,
        };
        return if (metatable) |table| .{ .table = table } else .nil;
    }

    fn getMetatableValue(self: *State, value: Value) !Value {
        const metatable = switch (value) {
            .table => |table| table.metatable orelse return .nil,
            .userdata => |userdata| userdata.metatable orelse return .nil,
            .string => self.string_metatable orelse return .nil,
            .integer, .number => self.number_metatable orelse return .nil,
            .boolean => self.boolean_metatable orelse return .nil,
            .nil => self.nil_metatable orelse return .nil,
            else => return .nil,
        };
        const locked = metatable.get(.{ .string = "__metatable" });
        if (locked != .nil) return locked;
        return .{ .table = metatable };
    }

    fn setMetatableValue(self: *State, table_value: Value, metatable_value: Value) !void {
        const table = try self.expectTable(table_value);
        if (table.metatable) |metatable| {
            if (metatable.get(.{ .string = "__metatable" }) != .nil) return self.failLibrary("cannot change a protected metatable");
        }
        const metatable = switch (metatable_value) {
            .nil => null,
            .table => |metatable| metatable,
            else => return self.fail("nil or table expected"),
        };
        self.setTableMetatableRaw(table, metatable);
        if (table.metatable) |active_metatable| self.writeBarrier(table, .{ .table = active_metatable });
    }

    pub fn setDebugMetatableValue(self: *State, value: Value, metatable_value: Value) !void {
        const metatable = switch (metatable_value) {
            .nil => null,
            .table => |metatable| metatable,
            else => return self.fail("nil or table expected"),
        };
        switch (value) {
            .table => |table| {
                self.setTableMetatableRaw(table, metatable);
                if (metatable) |mt| self.writeBarrier(table, .{ .table = mt });
            },
            .userdata => |userdata| {
                rollback_mod.touch(userdata);
                userdata.metatable = metatable;
                if (metatable) |mt| self.writeBarrier(userdata, .{ .table = mt });
                self.checkUserdataFinalizer(userdata);
            },
            .string => self.string_metatable = metatable,
            .integer, .number => self.number_metatable = metatable,
            .boolean => self.boolean_metatable = metatable,
            .nil => self.nil_metatable = metatable,
            else => return self.fail("cannot set metatable for this value"),
        }
        if (metatable) |mt| self.markValue(.{ .table = mt });
    }

    pub fn getMetamethod(self: *State, value: Value, name: []const u8) !?Value {
        if (types.MetaEvent.fromName(name)) |event| return self.getMetaEvent(value, event);
        const metatable = switch (value) {
            .table => |table| table.metatable orelse return null,
            .userdata => |userdata| userdata.metatable orelse return null,
            .string => self.string_metatable orelse return null,
            .integer, .number => self.number_metatable orelse return null,
            .boolean => self.boolean_metatable orelse return null,
            .nil => self.nil_metatable orelse return null,
            else => return null,
        };
        const metamethod = metatable.get(.{ .string = name });
        return if (metamethod == .nil) null else metamethod;
    }

    pub fn getMetaEvent(self: *State, value: Value, event: types.MetaEvent) !?Value {
        const metatable = switch (value) {
            .table => |table| table.metatable orelse return null,
            .userdata => |userdata| userdata.metatable orelse return null,
            .string => self.string_metatable orelse return null,
            .integer, .number => self.number_metatable orelse return null,
            .boolean => self.boolean_metatable orelse return null,
            .nil => self.nil_metatable orelse return null,
            else => return null,
        };
        const metamethod = metatable.metaEvent(event);
        return if (metamethod == .nil) null else metamethod;
    }

    pub fn setTableMetatableRaw(self: *State, table: *Table, metatable: ?*Table) void {
        rollback_mod.touch(table);
        const old_has_metatable = table.metatable != null;
        table.metatable = metatable;
        self.noteTableMetatableChanged(table, old_has_metatable);
        if (metatable) |mt| self.writeBarrier(table, .{ .table = mt });
    }

    /// Like `luaC_checkfinalizer` when a metatable is set.
    pub fn checkUserdataFinalizer(self: *State, userdata: *Userdata) void {
        gc_mod.checkUserdataFinalizer(State, self, userdata);
    }

    pub fn nextFinalizerOrder(self: *State) u64 {
        self.table_finalizer_serial += 1;
        return self.table_finalizer_serial;
    }

    pub fn noteTableMetatableChanged(self: *State, table: *Table, old_has_metatable: bool) void {
        return gc_mod.noteTableMetatableChanged(State, self, table, old_has_metatable);
    }

    pub fn unlinkTableMetatable(self: *State, table: *Table) void {
        return gc_mod.unlinkTableMetatable(State, self, table);
    }

    pub fn luaTypeNameForError(self: *State, value: Value) []const u8 {
        if (self.getMetaEvent(value, .__name) catch null) |name| {
            if (name == .string) return name.string;
        }
        return luaTypeName(value);
    }

    fn getEitherMetamethod(self: *State, lhs: Value, rhs: Value, name: []const u8) !?Value {
        if (types.MetaEvent.fromName(name)) |event| {
            if (try self.getMetaEvent(lhs, event)) |metamethod| return metamethod;
            return self.getMetaEvent(rhs, event);
        }
        if (try self.getMetamethod(lhs, name)) |metamethod| return metamethod;
        return self.getMetamethod(rhs, name);
    }

    fn binaryOpToRegister(self: *State, thread: *Thread, op: bytecode.Binary, kind: BinaryOp) !void {
        const lhs = self.get(thread, op.left);
        const rhs = self.get(thread, op.right);
        if (kind == .concat and luaStringLike(lhs) and luaStringLike(rhs)) {
            self.set(thread, op.dest, try self.concatValues(lhs, rhs));
            return;
        }
        const raw = rawBinaryOp(lhs, rhs, kind) catch |err| switch (err) {
            error.RuntimeError => if ((kind == .idiv or kind == .mod) and (toInteger(rhs) orelse 1) == 0) return self.failDivisionByZero(thread, lhs, rhs, kind) else return err,
        };
        if (raw) |value| {
            self.set(thread, op.dest, value);
            return;
        }

        const metamethod_name = binaryMetamethod(kind);
        const metamethod = (try self.getEitherMetamethod(lhs, rhs, metamethod_name)) orelse {
            return self.failBinaryTypeError(thread, lhs, rhs, kind);
        };
        const result = try self.callOneMetamethodWithContinuation(thread, metamethod_name, metamethod, &.{ lhs, rhs }, .{ .value = self.absoluteRegister(thread, op.dest) });
        self.set(thread, op.dest, result);
    }

    fn unaryOpToRegister(self: *State, thread: *Thread, op: bytecode.Unary, kind: UnaryMetamethodOp) !void {
        const value = self.get(thread, op.source);
        if (rawUnaryOp(value, kind)) |result| {
            self.set(thread, op.dest, result);
            return;
        }
        const metamethod = (try self.getMetamethod(value, unaryMetamethod(kind))) orelse return self.failUnaryTypeError(thread, value, kind);
        const result = try self.callOneMetamethodWithContinuation(thread, unaryMetamethod(kind), metamethod, &.{ value, value }, .{ .value = self.absoluteRegister(thread, op.dest) });
        self.set(thread, op.dest, result);
    }

    fn equalValuesToRegister(self: *State, thread: *Thread, op: bytecode.Binary) !void {
        const lhs = self.get(thread, op.left);
        const rhs = self.get(thread, op.right);
        if (valuesEqual(lhs, rhs)) {
            self.set(thread, op.dest, .{ .boolean = true });
            return;
        }
        if (!equalityHasMetamethod(lhs, rhs)) {
            self.set(thread, op.dest, .{ .boolean = false });
            return;
        }
        const metamethod = (try self.getEitherMetamethod(lhs, rhs, "__eq")) orelse {
            self.set(thread, op.dest, .{ .boolean = false });
            return;
        };
        const result = try self.callOneMetamethodWithContinuation(thread, "__eq", metamethod, &.{ lhs, rhs }, .{ .truthy = self.absoluteRegister(thread, op.dest) });
        self.set(thread, op.dest, .{ .boolean = truthy(result) });
    }

    fn compareValuesToRegister(self: *State, thread: *Thread, op: bytecode.Binary, kind: CompareOp) !void {
        const lhs = self.get(thread, op.left);
        const rhs = self.get(thread, op.right);
        if (rawCompare(lhs, rhs, kind)) |result| {
            self.set(thread, op.dest, .{ .boolean = result });
            return;
        }
        switch (kind) {
            .lt => {
                const metamethod = (try self.getEitherMetamethod(lhs, rhs, "__lt")) orelse return self.failCompareTypeError(thread, lhs, rhs);
                const result = try self.callOneMetamethodWithContinuation(thread, "__lt", metamethod, &.{ lhs, rhs }, .{ .truthy = self.absoluteRegister(thread, op.dest) });
                self.set(thread, op.dest, .{ .boolean = truthy(result) });
            },
            .le => {
                if (try self.getEitherMetamethod(lhs, rhs, "__le")) |metamethod| {
                    const result = try self.callOneMetamethodWithContinuation(thread, "__le", metamethod, &.{ lhs, rhs }, .{ .truthy = self.absoluteRegister(thread, op.dest) });
                    self.set(thread, op.dest, .{ .boolean = truthy(result) });
                    return;
                }
                const lt = (try self.getEitherMetamethod(lhs, rhs, "__lt")) orelse return self.failCompareTypeError(thread, lhs, rhs);
                const result = try self.callOneMetamethodWithContinuation(thread, "__lt", lt, &.{ rhs, lhs }, .{ .inverted_truthy = self.absoluteRegister(thread, op.dest) });
                self.set(thread, op.dest, .{ .boolean = !truthy(result) });
            },
        }
    }

    fn compareBranch(self: *State, thread: *Thread, op: bytecode.CompareBranch) !void {
        const lhs = self.get(thread, op.left);
        const rhs = self.get(thread, op.right);
        switch (op.op) {
            .eq => {
                if (valuesEqual(lhs, rhs)) return self.jumpIfBranchResult(thread, true, op.jump_if_truthy, op.offset);
                if (!equalityHasMetamethod(lhs, rhs)) return self.jumpIfBranchResult(thread, false, op.jump_if_truthy, op.offset);
                const metamethod = (try self.getEitherMetamethod(lhs, rhs, "__eq")) orelse return self.jumpIfBranchResult(thread, false, op.jump_if_truthy, op.offset);
                const continuation: BranchContinuation = .{ .jump_if_truthy = op.jump_if_truthy, .offset = op.offset };
                const result = try self.callOneMetamethodWithContinuation(thread, "__eq", metamethod, &.{ lhs, rhs }, .{ .branch_truthy = continuation });
                try self.jumpIfBranchResult(thread, truthy(result), op.jump_if_truthy, op.offset);
            },
            .lt => try self.compareBranchOrder(thread, lhs, rhs, .lt, "__lt", op.jump_if_truthy, op.offset),
            .le => {
                if (rawCompare(lhs, rhs, .le)) |result| return self.jumpIfBranchResult(thread, result, op.jump_if_truthy, op.offset);
                if (try self.getEitherMetamethod(lhs, rhs, "__le")) |metamethod| {
                    const continuation: BranchContinuation = .{ .jump_if_truthy = op.jump_if_truthy, .offset = op.offset };
                    const result = try self.callOneMetamethodWithContinuation(thread, "__le", metamethod, &.{ lhs, rhs }, .{ .branch_truthy = continuation });
                    return self.jumpIfBranchResult(thread, truthy(result), op.jump_if_truthy, op.offset);
                }
                const lt = (try self.getEitherMetamethod(lhs, rhs, "__lt")) orelse return self.failCompareTypeError(thread, lhs, rhs);
                const continuation: BranchContinuation = .{ .jump_if_truthy = op.jump_if_truthy, .offset = op.offset };
                const result = try self.callOneMetamethodWithContinuation(thread, "__lt", lt, &.{ rhs, lhs }, .{ .branch_inverted_truthy = continuation });
                try self.jumpIfBranchResult(thread, !truthy(result), op.jump_if_truthy, op.offset);
            },
        }
    }

    fn compareBranchOrder(self: *State, thread: *Thread, lhs: Value, rhs: Value, kind: CompareOp, metamethod_name: []const u8, jump_if_truthy: bool, offset: bytecode.JumpOffset) !void {
        if (rawCompare(lhs, rhs, kind)) |result| return self.jumpIfBranchResult(thread, result, jump_if_truthy, offset);
        const metamethod = (try self.getEitherMetamethod(lhs, rhs, metamethod_name)) orelse return self.failCompareTypeError(thread, lhs, rhs);
        const continuation: BranchContinuation = .{ .jump_if_truthy = jump_if_truthy, .offset = offset };
        const result = try self.callOneMetamethodWithContinuation(thread, metamethod_name, metamethod, &.{ lhs, rhs }, .{ .branch_truthy = continuation });
        try self.jumpIfBranchResult(thread, truthy(result), jump_if_truthy, offset);
    }

    pub fn jumpIfBranchResult(self: *State, thread: *Thread, result: bool, jump_if_truthy: bool, offset: bytecode.JumpOffset) !void {
        if (result == jump_if_truthy) try self.jumpThreadMaybeFast(thread, offset, true);
    }

    fn lengthToRegister(self: *State, thread: *Thread, op: bytecode.Unary) !void {
        const value = self.get(thread, op.source);
        switch (value) {
            .string => |string| self.set(thread, op.dest, .{ .integer = @intCast(string.len) }),
            .table => |table| if ((try self.getMetaEvent(value, .__len))) |metamethod| {
                const result = try self.callOneMetamethodWithContinuation(thread, "__len", metamethod, &.{ value, value }, .{ .value = self.absoluteRegister(thread, op.dest) });
                self.set(thread, op.dest, result);
            } else {
                self.set(thread, op.dest, .{ .integer = table.len() });
            },
            else => if ((try self.getMetaEvent(value, .__len))) |metamethod| {
                const result = try self.callOneMetamethodWithContinuation(thread, "__len", metamethod, &.{ value, value }, .{ .value = self.absoluteRegister(thread, op.dest) });
                self.set(thread, op.dest, result);
            } else {
                return self.failLengthTypeError(thread, value);
            },
        }
    }

    fn rawLen(self: *State, value: Value) !Value {
        return switch (value) {
            .string => |string| .{ .integer = @intCast(string.len) },
            .table => |table| .{ .integer = table.len() },
            else => self.fail("table or string expected"),
        };
    }

    fn binaryOp(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: BinaryOp) !Value {
        if (op == .concat and luaStringLike(lhs) and luaStringLike(rhs)) return self.concatValues(lhs, rhs);
        const raw = rawBinaryOp(lhs, rhs, op) catch |err| switch (err) {
            error.RuntimeError => if ((op == .idiv or op == .mod) and (toInteger(rhs) orelse 1) == 0) return self.failDivisionByZero(thread, lhs, rhs, op) else return err,
        };
        if (raw) |value| return value;
        const metamethod_name = binaryMetamethod(op);
        const metamethod = (try self.getEitherMetamethod(lhs, rhs, metamethod_name)) orelse {
            return self.failBinaryTypeError(thread, lhs, rhs, op);
        };
        return self.callOneMetamethod(thread, metamethod_name, metamethod, &.{ lhs, rhs });
    }

    fn unaryOp(self: *State, thread: *Thread, value: Value, op: UnaryMetamethodOp) !Value {
        if (rawUnaryOp(value, op)) |result| return result;
        const metamethod_name = unaryMetamethod(op);
        const metamethod = (try self.getMetamethod(value, metamethod_name)) orelse return self.failUnaryTypeError(thread, value, op);
        return self.callOneMetamethod(thread, metamethod_name, metamethod, &.{ value, value });
    }

    fn equalValues(self: *State, thread: *Thread, lhs: Value, rhs: Value) !bool {
        if (valuesEqual(lhs, rhs)) return true;
        if (!equalityHasMetamethod(lhs, rhs)) return false;
        const metamethod = (try self.getEitherMetamethod(lhs, rhs, "__eq")) orelse return false;
        return truthy(try self.callOneMetamethod(thread, "__eq", metamethod, &.{ lhs, rhs }));
    }

    pub fn compareValues(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: CompareOp) !bool {
        if (rawCompare(lhs, rhs, op)) |result| return result;
        switch (op) {
            .lt => {
                const metamethod = (try self.getEitherMetamethod(lhs, rhs, "__lt")) orelse return self.failCompareTypeError(thread, lhs, rhs);
                return truthy(try self.callOneMetamethod(thread, "__lt", metamethod, &.{ lhs, rhs }));
            },
            .le => {
                if (try self.getEitherMetamethod(lhs, rhs, "__le")) |metamethod| {
                    return truthy(try self.callOneMetamethod(thread, "__le", metamethod, &.{ lhs, rhs }));
                }
                const lt = (try self.getEitherMetamethod(lhs, rhs, "__lt")) orelse return self.failCompareTypeError(thread, lhs, rhs);
                return !truthy(try self.callOneMetamethod(thread, "__lt", lt, &.{ rhs, lhs }));
            },
        }
    }

    fn checkStackValueOverflow(self: *State, thread: *Thread, needed: usize) !void {
        if (!thread.stack_error_space) {
            thread.stack_error_space = true;
            return self.failRuntimeDetail(thread, "stack overflow");
        }
        if (needed <= self.stackValueLimit() + stack_error_values) return;
        _ = try self.errorInErrorHandling();
        return error.RuntimeError;
    }

    /// Like `lua_checkstack`, above the arguments of native call `op`.
    pub fn nativeStackFits(self: *const State, thread: *const Thread, op: bytecode.Call, count: usize) bool {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const top = frame.base + op.base + 1 + op.arg_count;
        return count <= self.stackValueLimit() -| top;
    }

    pub fn callStackValueLimit(self: *const State, thread: *const Thread) usize {
        return self.stackValueLimit() + if (thread.stack_error_space) stack_error_values else 0;
    }

    fn checkFrameOverflow(self: *State, thread: *Thread) !void {
        if (!thread.stack_error_space) {
            thread.stack_error_space = true;
            return self.failRuntimeDetail(thread, "stack overflow");
        }
        if (thread.frames.items.len < self.callFrameLimit() + stack_error_frames) return;
        _ = try self.errorInErrorHandling();
        return error.RuntimeError;
    }

    fn callClosure(self: *State, thread: *Thread, op: bytecode.Call, closure: *Closure, debug_name_override: ?[]const u8, debug_namewhat_override: ?[]const u8) !void {
        if (thread.frames.items.len >= self.callFrameLimit()) try self.checkFrameOverflow(thread);

        const caller = thread.frames.items[thread.frames.items.len - 1];
        const base = caller.base + op.base;
        if (base + 1 + @max(closure.proto.max_registers, 1) > self.stackValueLimit()) try self.checkStackValueOverflow(thread, base + 1 + @max(closure.proto.max_registers, 1));
        var frame = try self.prepareClosureFrame(thread, closure, base, base + 1, @intCast(op.arg_count), base, op.return_count);
        frame.debug_name_override = debug_name_override;
        frame.debug_namewhat_override = debug_namewhat_override;
        errdefer thread.releaseFrame(&frame, self.allocator);
        try thread.frames.append(self.allocator, frame);
        if (thread.hook_call and !thread.hook_running) try self.callHook(thread, "call");
    }

    fn tailCallValue(self: *State, thread: *Thread, op: bytecode.Call) anyerror!void {
        var resolved = try self.resolveCall(thread, op);
        var depth: usize = 0;
        while (true) {
            const callee = self.get(thread, resolved.base);
            switch (callee) {
                .closure => break,
                .coroutine_wrapper => break,
                else => if (isNativeCallable(callee)) break,
            }

            if (depth > max_metamethod_depth) return self.fail("'__call' chain too long");
            const metamethod = try self.getMetaEvent(callee, .__call) orelse break;
            try self.prependCallArgument(thread, resolved, metamethod, callee);
            resolved.arg_count += 1;
            depth += 1;
        }

        const callee = self.get(thread, resolved.base);
        switch (callee) {
            .closure => |closure| {
                try self.closeActiveToBeClosedInTopFrame(thread, null);
                const frame = thread.frames.items[thread.frames.items.len - 1];
                self.closeUpvalues(thread, frame.base);
                const new_frame = try self.prepareClosureFrame(thread, closure, frame.base + resolved.base, frame.base, @intCast(resolved.arg_count), frame.return_start, frame.return_count);
                var tail_frame = new_frame;
                tail_frame.is_tail_call = true;
                thread.releaseFrame(&thread.frames.items[thread.frames.items.len - 1], self.allocator);
                thread.frames.items[thread.frames.items.len - 1] = tail_frame;
                if (thread.hook_call and !thread.hook_running) {
                    const previous_transfer_index_base = thread.hook_transfer_index_base;
                    const previous_transfer_stack_base = thread.hook_transfer_stack_base;
                    const previous_transfer_count = thread.hook_transfer_count;
                    const previous_transfer_values = thread.hook_transfer_values;
                    thread.hook_transfer_index_base = 1;
                    thread.hook_transfer_stack_base = new_frame.base;
                    thread.hook_transfer_count = closure.proto.param_count;
                    thread.hook_transfer_values = &.{};
                    defer {
                        thread.hook_transfer_index_base = previous_transfer_index_base;
                        thread.hook_transfer_stack_base = previous_transfer_stack_base;
                        thread.hook_transfer_count = previous_transfer_count;
                        thread.hook_transfer_values = previous_transfer_values;
                    }
                    try self.callHook(thread, "tail call");
                }
            },
            else => {
                const frame = thread.frames.items[thread.frames.items.len - 1];
                const frame_count = thread.frames.items.len;
                self.invokeValue(thread, .{ .base = resolved.base, .arg_count = resolved.arg_count, .return_count = frame.return_count }, depth) catch |err| switch (err) {
                    error.CoroutineYield => {
                        try self.pushTailCallContinuation(thread, frame_count, resolved.base, frame.return_count);
                        return err;
                    },
                    else => return err,
                };
                try self.runThreadUntil(thread, frame_count);
                try self.returnFromFrame(thread, resolved.base, frame.return_count);
            },
        }
    }

    fn returnFromFrame(self: *State, thread: *Thread, first: u32, count: u16) !void {
        const frame_index = thread.frames.items.len - 1;
        var frame = &thread.frames.items[frame_index];
        if (frame.pending_returns == null and !frame.proto.has_to_close_locals and (!thread.hook_return or thread.hook_running)) {
            const source_start = frame.base + first;
            const source_count = try self.resolveResultCount(thread, source_start, count);
            self.closeUpvalues(thread, frame.base);
            if (thread.frames.items.len == 1) {
                thread.last_result_base = source_start;
                thread.last_result_count = source_count;
                thread.releaseFrame(frame, self.allocator);
                thread.frames.items.len = 0;
                return;
            }

            const return_start = frame.return_start;
            const return_count = try self.resolveReturnCount(frame.return_count, source_count);
            thread.releaseFrame(frame, self.allocator);
            thread.frames.items.len -= 1;

            try thread.ensureStack(self.allocator, return_start + return_count, self.callStackValueLimit(thread));
            const copied = @min(return_count, source_count);
            for (0..copied) |index| thread.stack.items[return_start + index] = thread.stack.items[source_start + index];
            for (copied..return_count) |index| thread.stack.items[return_start + index] = .nil;
            thread.last_result_base = return_start;
            thread.last_result_count = return_count;
            return;
        }

        const preserved = frame.pending_returns orelse blk: {
            const source_start = frame.base + first;
            const source_count = try self.resolveResultCount(thread, source_start, count);
            const values = try self.allocator.alloc(Value, source_count);
            for (values, 0..) |*value, index| value.* = thread.stack.items[source_start + index];
            frame.pending_returns = values;
            thread.frame_storage_bytes += values.len * @sizeOf(Value);
            break :blk values;
        };
        try self.closeActiveToBeClosedInTopFrame(thread, null);
        frame = &thread.frames.items[frame_index];
        if (thread.hook_return and !thread.hook_running) {
            const previous_transfer_index_base = thread.hook_transfer_index_base;
            const previous_transfer_stack_base = thread.hook_transfer_stack_base;
            const previous_transfer_count = thread.hook_transfer_count;
            const previous_transfer_values = thread.hook_transfer_values;
            thread.hook_transfer_index_base = @as(i64, @intCast(first)) + 1;
            thread.hook_transfer_stack_base = frame.base + first;
            thread.hook_transfer_count = preserved.len;
            thread.hook_transfer_values = preserved;
            defer {
                thread.hook_transfer_index_base = previous_transfer_index_base;
                thread.hook_transfer_stack_base = previous_transfer_stack_base;
                thread.hook_transfer_count = previous_transfer_count;
                thread.hook_transfer_values = previous_transfer_values;
            }
            try self.callReturnHook(thread, frame.debug_name_override orelse frame.proto.debug_name);
        }
        frame = &thread.frames.items[frame_index];
        frame.pending_returns = null;
        thread.frame_storage_bytes -= preserved.len * @sizeOf(Value);
        defer self.allocator.free(preserved);
        self.closeUpvalues(thread, frame.base);
        if (thread.frames.items.len == 1) {
            const result_start = frame.base + first;
            try thread.ensureStack(self.allocator, result_start + preserved.len, self.callStackValueLimit(thread));
            for (preserved, 0..) |value, index| thread.stack.items[result_start + index] = value;
            thread.last_result_base = result_start;
            thread.last_result_count = preserved.len;
            thread.releaseFrame(frame, self.allocator);
            thread.frames.items.len = 0;
            return;
        }

        const return_start = frame.return_start;
        const return_count = try self.resolveReturnCount(frame.return_count, preserved.len);
        thread.releaseFrame(frame, self.allocator);
        thread.frames.items.len -= 1;

        try thread.ensureStack(self.allocator, return_start + return_count, self.callStackValueLimit(thread));
        const copied = @min(return_count, preserved.len);
        for (preserved[0..copied], 0..) |value, index| thread.stack.items[return_start + index] = value;
        for (copied..return_count) |index| thread.stack.items[return_start + index] = .nil;
        thread.last_result_base = return_start;
        thread.last_result_count = return_count;
    }

    pub fn returnValues(self: *State, thread: *Thread, base: u32, return_count: u16, values: []const Value) !void {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const actual_count = try self.resolveReturnCount(return_count, values.len);
        const absolute_base = frame.base + base;
        const stored_count = @max(actual_count, values.len);
        try thread.ensureStack(self.allocator, absolute_base + stored_count, self.callStackValueLimit(thread));
        for (0..stored_count) |index| {
            thread.stack.items[absolute_base + index] = if (index < values.len) values[index] else .nil;
        }
        thread.last_result_base = absolute_base;
        thread.last_result_count = actual_count;
        thread.last_transfer_base = absolute_base;
        thread.last_transfer_count = values.len;
    }

    pub fn prepareClosureFrame(self: *State, thread: *Thread, closure: *Closure, source_base: usize, frame_base: usize, arg_count: usize, return_start: usize, return_count: u16) !CallFrame {
        return call_mod.prepareClosureFrame(State, self, thread, closure, source_base, frame_base, arg_count, return_start, return_count);
    }

    pub fn captureVarargs(self: *State, thread: *Thread, source_start: usize, count: usize) ![]const Value {
        if (count == 0) return &.{};
        const values = try self.allocator.alloc(Value, count);
        for (0..count) |index| values[index] = thread.stack.items[source_start + index];
        return values;
    }

    pub fn namedVarargTable(self: *State, varargs: []const Value) !Value {
        const table_value = try self.newTableWithHints(@intCast(varargs.len), 1);
        const table = table_value.table;
        try self.setTableRaw(table, .{ .string = try self.intern("n") }, .{ .integer = @intCast(varargs.len) });
        for (varargs, 0..) |value, index| {
            try self.setTableRaw(table, .{ .integer = @intCast(index + 1) }, value);
        }
        return table_value;
    }

    fn namedVarargRead(varargs: []const Value, key: Value) Value {
        if (key == .string and std.mem.eql(u8, key.string, "n")) return .{ .integer = @intCast(varargs.len) };
        const normalized: Value = if (key == .number) .{ .integer = floatToInteger(key.number) orelse return .nil } else key;
        if (arrayIndex(normalized)) |index| {
            if (index <= varargs.len) return varargs[index - 1];
        }
        return .nil;
    }

    fn resolveCall(self: *State, thread: *Thread, op: bytecode.Call) !bytecode.Call {
        if (op.arg_count != bytecode.multret_arg_count) return op;
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const expected_base = frame.base + op.base + 1;
        if (thread.last_result_base < expected_base) return self.fail("invalid multiple-return call state");
        const end = thread.last_result_base + thread.last_result_count;
        const count = if (end <= expected_base) 0 else end - expected_base;
        return .{ .base = op.base, .arg_count = @intCast(count), .return_count = op.return_count };
    }

    fn resolveResultCount(self: *State, thread: *Thread, source_start: usize, count: u16) !usize {
        if (count != bytecode.multret_count) return count;
        if (thread.last_result_base < source_start) return self.fail("invalid multiple-return result state");
        const end = thread.last_result_base + thread.last_result_count;
        return if (end <= source_start) 0 else end - source_start;
    }

    pub fn resolveReturnCount(self: *State, count: u16, available: usize) !usize {
        return call_mod.resolveReturnCount(State, self, count, available);
    }

    fn loadVarargs(self: *State, thread: *Thread, op: bytecode.Vararg) !void {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        if (frame.proto.named_vararg and !frame.named_vararg_readonly) return self.loadNamedVarargs(thread, frame, op);
        const actual_count = try self.resolveReturnCount(op.count, frame.varargs.len);
        const dest = frame.base + op.dest;
        try thread.ensureStack(self.allocator, dest + actual_count, self.callStackValueLimit(thread));
        const copied = @min(actual_count, frame.varargs.len);
        for (0..copied) |index| thread.stack.items[dest + index] = frame.varargs[index];
        for (copied..actual_count) |index| thread.stack.items[dest + index] = .nil;
        thread.last_result_base = dest;
        thread.last_result_count = actual_count;
    }

    fn loadNamedVarargs(self: *State, thread: *Thread, frame: CallFrame, op: bytecode.Vararg) !void {
        const table_value = thread.stack.items[frame.base + frame.proto.param_count];
        const table = try self.expectTable(table_value);
        const count = try self.namedVarargCount(table);
        const actual_count = try self.resolveReturnCount(op.count, count);
        const dest = frame.base + op.dest;
        try thread.ensureStack(self.allocator, dest + actual_count, self.callStackValueLimit(thread));
        const copied = @min(actual_count, count);
        for (0..copied) |index| thread.stack.items[dest + index] = table.get(.{ .integer = @intCast(index + 1) });
        for (copied..actual_count) |index| thread.stack.items[dest + index] = .nil;
        thread.last_result_base = dest;
        thread.last_result_count = actual_count;
    }

    fn namedVarargCount(self: *State, table: *Table) !usize {
        const n_value = table.get(.{ .string = try self.intern("n") });
        if (n_value != .integer or n_value.integer < 0 or n_value.integer >= bytecode.multret_count) {
            return self.fail("vararg table has no proper 'n'");
        }
        return @intCast(n_value.integer);
    }

    fn setList(self: *State, thread: *Thread, op: bytecode.SetList) !void {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const source_start = frame.base + op.first;
        const count: usize = if (op.count == bytecode.multret_count) try self.resolveResultCount(thread, source_start, bytecode.multret_count) else op.count;
        const table_value = self.get(thread, op.table);
        if (try self.fastSetListRaw(thread, table_value, source_start, count, op.start_index)) return;
        for (0..count) |index| {
            const array_index = @as(usize, op.start_index) + index;
            try self.setTable(table_value, .{ .integer = @intCast(array_index) }, thread.stack.items[source_start + index]);
        }
    }

    fn fastSetListRaw(self: *State, thread: *Thread, table_value: Value, source_start: usize, count: usize, start_index_u32: u32) !bool {
        if (table_value != .table or start_index_u32 == 0) return false;
        const table = table_value.table;
        defer self.noteTableCapacityDelta(table, 0);
        try rollback_mod.tableWritable(table);
        if (table.metatable != null) return false;

        const start_index: usize = start_index_u32;
        var grow_to = table.array.items.len;
        for (0..count) |offset| {
            if (offset > std.math.maxInt(usize) - start_index) return self.fail("table overflow");
            const array_index = start_index + offset;
            if (array_index > std.math.maxInt(i64)) return false;
            if (thread.stack.items[source_start + offset] != .nil and array_index > grow_to) grow_to = array_index;
        }

        if (grow_to > table.array.items.len and start_index > table.array.items.len + 1 and grow_to > table.array.capacity) return false;
        if (grow_to > table.array.items.len) {
            const old_capacity_bytes = tableCapacityBytes(table);
            const old_len = table.array.items.len;
            try table.array.resize(self.allocator, grow_to);
            @memset(table.array.items[old_len..], .nil);
            self.noteTableCapacityDelta(table, old_capacity_bytes);
        }

        for (0..count) |offset| {
            const array_index = start_index + offset;
            if (array_index > table.array.items.len) continue;
            const value = thread.stack.items[source_start + offset];
            table.array.items[array_index - 1] = value;
            const key = Value{ .integer = @intCast(array_index) };
            if (value != .nil) table.removeHashKey(key);
            self.writeTableBarrier(table, key, value);
        }
        return true;
    }

    fn selectValues(self: *State, thread: *Thread, op: bytecode.Call) !void {
        const first = argValue(self, thread, op, 0);
        if (first == .string and std.mem.eql(u8, first.string, "#")) {
            try self.returnValues(thread, op.base, op.return_count, &.{.{ .integer = @intCast(op.arg_count - 1) }});
            return;
        }

        var index = try self.argumentInteger(thread, op, "select", 0);
        const count: i64 = @intCast(op.arg_count - 1);
        if (index < 0) index = count + index + 1;
        if (index < 1 or index > count + 1) return self.failArgumentMessage("select", 1, "index out of range");

        var values = std.ArrayList(Value).empty;
        defer values.deinit(self.allocator);
        var arg_index: usize = @intCast(index);
        const last_arg: usize = @intCast(count);
        while (arg_index <= last_arg) : (arg_index += 1) {
            try values.append(self.allocator, argValue(self, thread, op, @intCast(arg_index)));
        }
        try self.returnValues(thread, op.base, op.return_count, values.items);
    }

    fn assertValues(self: *State, thread: *Thread, op: bytecode.Call) !void {
        if (op.arg_count == 0) return self.failArgumentMessage("assert", 1, "value expected");

        const condition = argValue(self, thread, op, 0);
        if (!truthy(condition)) {
            const message = if (op.arg_count >= 2) argValue(self, thread, op, 1) else Value{ .string = "assertion failed!" };
            if (message == .string) return self.throwStringWithLocation(thread, message.string, 1);
            return self.throwValue(message);
        }

        const values = try self.allocator.alloc(Value, op.arg_count);
        defer self.allocator.free(values);
        for (values, 0..) |*value, index| value.* = argValue(self, thread, op, @intCast(index));
        try self.returnValues(thread, op.base, op.return_count, values);
    }

    fn errorValue(self: *State, thread: *Thread, op: bytecode.Call) !void {
        const value = argValue(self, thread, op, 0);
        const level = if (op.arg_count >= 2) toInteger(argValue(self, thread, op, 1)) orelse 1 else 1;
        if (level <= 0 or value != .string) return self.throwValue(value);

        const level_index = std.math.cast(usize, level) orelse return self.throwValue(value);
        return self.throwStringWithLocation(thread, value.string, level_index);
    }

    fn throwStringWithLocation(self: *State, thread: *Thread, message_text: []const u8, requested_level: usize) !void {
        var level = requested_level;
        if (activeNativeCall(thread)) |call| {
            if (call.from_native) {
                if (level == 1) return self.throwValue(.{ .string = try self.intern(message_text) });
                level -= 1;
            } else if (level >= 2 and call.outer_frame_count != null and call.outer_frame_count.? + 1 == call.frame_count) {
                if (level == 2) return self.throwValue(.{ .string = try self.intern(message_text) });
                level -= 1;
            }
        }
        const line = self.lineForErrorLevel(thread, level) orelse return self.throwValue(.{ .string = try self.intern(message_text) });
        const source = self.sourceForErrorLevel(thread, level) orelse "zlua";
        const message = try std.fmt.allocPrint(self.allocator, "{s}:{d}: {s}", .{ source, line, message_text });
        defer self.allocator.free(message);
        return self.throwValue(.{ .string = try self.intern(message) });
    }

    /// Like `luaG_errormsg` without a handler: nil becomes `<no error object>`.
    pub fn caughtErrorValue(self: *State, value: Value) !Value {
        if (value == .nil) return .{ .string = try self.intern("<no error object>") };
        return value;
    }

    fn pcallValues(self: *State, thread: *Thread, op: bytecode.Call) !void {
        if (op.arg_count == 0) return self.failArgumentMessage("pcall", 1, "value expected");
        const args = try self.collectArgs(thread, op, 1);
        defer self.allocator.free(args);
        try self.protectedCallValues(thread, op, argValue(self, thread, op, 0), args, .nil);
    }

    fn xpcallValues(self: *State, thread: *Thread, op: bytecode.Call) !void {
        const handler = argValue(self, thread, op, 1);
        if (!functionLike(handler)) return self.failArgumentType("xpcall", 2, "function", handler);
        const args = try self.collectArgs(thread, op, 2);
        defer self.allocator.free(args);
        try self.protectedCallValues(thread, op, argValue(self, thread, op, 0), args, handler);
    }

    fn protectedCallValues(self: *State, thread: *Thread, op: bytecode.Call, callable: Value, args: []const Value, handler: Value) !void {
        var context = self.protectedCallContextWithErrors(thread);
        context.error_handler = handler;
        const result = self.runProtectedCall(thread, context, callable, args) catch |err| switch (err) {
            error.CoroutineYield => {
                try self.pushProtectedContinuation(thread, context, op.base, op.return_count);
                return err;
            },
            else => return err,
        };
        defer freeProtectedResult(self.allocator, result);
        try self.returnProtectedResult(thread, op.base, op.return_count, result);
    }

    fn tracebackValue(self: *State, thread: *Thread, op: bytecode.Call) !void {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);

        const message = argValue(self, thread, op, 0);
        if (message == .thread) {
            const target = message.thread;
            const level_value = if (op.arg_count >= 3) argValue(self, thread, op, 2) else Value.nil;
            const has_coroutine_level = level_value != .nil;
            if (!has_coroutine_level and target.close_error_value != null) if (target.error_traceback) |traceback| {
                try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = traceback }});
                return;
            };
            const coroutine_level = if (has_coroutine_level) toInteger(level_value) orelse 1 else 0;
            const has_yield_trace = !has_coroutine_level and (target.frames.items.len != 0 or (target.status != .dead and target.yield_values.items.len != 0));
            try out.appendSlice(self.allocator, "stack traceback:");
            if (has_yield_trace) try out.appendSlice(self.allocator, "\n\t'yield'");
            const skip = if (coroutine_level <= 1) @as(usize, 0) else @as(usize, @intCast(coroutine_level - 1));
            const count = if (skip >= target.frames.items.len) @as(usize, 0) else target.frames.items.len - skip;
            if (count == 0 and target.status != .dead and target.yield_values.items.len != 0 and !has_coroutine_level) {
                try out.appendSlice(self.allocator, "\n\t@db.lua: in function <");
            }
            try self.appendCoroutineTracebackFrames(&out, target, count, @intFromBool(has_yield_trace));
            try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.intern(out.items) }});
            return;
        }
        if (message != .nil and message != .string and message != .integer and message != .number) {
            try self.returnValues(thread, op.base, op.return_count, &.{message});
            return;
        }
        const text: ?[]const u8 = if (message == .nil) null else try self.valueToString(thread, message);
        const level = if (op.arg_count >= 2) toInteger(argValue(self, thread, op, 1)) orelse 1 else 1;
        if (level < 0) {
            try appendFmt(self.allocator, &out, "{s}{s}stack traceback:", .{ text orelse "", if (text == null) "" else "\n" });
            try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.intern(out.items) }});
            return;
        }
        const traceback = try debug_mod.formatTracebackWith(State, self, thread, .{
            .message = text,
            .level = std.math.cast(usize, level) orelse std.math.maxInt(usize),
            .level_zero_is_callee = calledByTopInstruction(thread, op),
            .level_zero = .native_debug_traceback,
            .host_frame = thread.host_frame,
        });
        defer self.allocator.free(traceback);
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.intern(traceback) }});
    }

    /// The standalone interpreter's `msghandler` from `lua.c`.
    pub fn tracebackMessageHandler(self: *State, thread: *Thread, op: bytecode.Call) !void {
        const message = argValue(self, thread, op, 0);
        const text = switch (message) {
            .string => |bytes| bytes,
            .integer, .number => try self.valueToString(thread, message),
            else => blk: {
                if (try self.getMetaEvent(message, .__tostring)) |metamethod| {
                    const result = try self.callOneResult(thread, metamethod, &.{message});
                    if (result == .string) return self.returnValues(thread, op.base, op.return_count, &.{result});
                }
                var out = std.ArrayList(u8).empty;
                defer out.deinit(self.allocator);
                try appendFmt(self.allocator, &out, "(error object is a {s} value)", .{luaTypeName(message)});
                break :blk try self.intern(out.items);
            },
        };
        const traceback = try debug_mod.formatTracebackWith(State, self, thread, .{ .message = text, .host_frame = thread.host_frame });
        defer self.allocator.free(traceback);
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.intern(traceback) }});
    }

    fn calledByTopInstruction(thread: *Thread, op: bytecode.Call) bool {
        const frames = thread.frames.items;
        if (frames.len == 0) return false;
        const frame = frames[frames.len - 1];
        if (frame.pc == 0 or frame.pc > frame.proto.instructions.items.len) return false;
        return switch (frame.proto.instructions.items[frame.pc - 1]) {
            .call, .tail_call => |call| call.base == op.base,
            else => false,
        };
    }

    fn appendCoroutineTracebackFrame(self: *State, out: *std.ArrayList(u8), target: *Thread, frame: CallFrame, level: i64) !void {
        try out.append(self.allocator, '\n');
        try out.append(self.allocator, '\t');
        try out.appendSlice(self.allocator, frame.proto.source_name);
        if (self.currentFunctionName(target, level)) |name| {
            try appendFmt(self.allocator, out, ": in function '{s}'", .{name});
        } else {
            try out.appendSlice(self.allocator, ": in function <");
        }
    }

    /// Appends the innermost `count` frames after `leading` levels, skipping the middle like `luaL_traceback`.
    fn appendCoroutineTracebackFrames(self: *State, out: *std.ArrayList(u8), target: *Thread, count: usize, leading: usize) !void {
        if (count == 0) return;
        const head = debug_mod.traceback_levels_head;
        const tail = debug_mod.traceback_levels_tail;
        const last = leading + count - 1;
        var level: usize = 0;
        var limit: isize = if (last > head + tail) head else -1;
        while (level <= last) {
            const current = level;
            level += 1;
            const show_skip = limit == 0;
            limit -= 1;
            if (show_skip) {
                const skipped = last - level - tail + 1;
                try appendFmt(self.allocator, out, "\n\t...\t(skipping {d} levels)", .{skipped});
                level += skipped;
                continue;
            }
            if (current < leading) continue;
            const index = count - 1 - (current - leading);
            try self.appendCoroutineTracebackFrame(out, target, target.frames.items[index], @intCast(target.frames.items.len - index));
        }
    }

    pub fn snapshotCoroutineErrorTraceback(self: *State, target: *Thread) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        try out.appendSlice(self.allocator, "stack traceback:\n\t'error'");
        try self.appendCoroutineTracebackFrames(&out, target, target.frames.items.len, 1);
        return self.intern(out.items);
    }

    pub fn coroutineCreate(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return coroutine_mod.coroutineCreate(State, self, thread, op);
    }

    pub fn coroutineResume(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return coroutine_mod.coroutineResume(State, self, thread, op);
    }

    pub fn coroutineYield(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return coroutine_mod.coroutineYield(State, self, thread, op);
    }

    pub fn coroutineStatus(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return coroutine_mod.coroutineStatus(State, self, thread, op);
    }

    pub fn coroutineRunning(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return coroutine_mod.coroutineRunning(State, self, thread, op);
    }

    pub fn coroutineIsYieldable(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return coroutine_mod.coroutineIsYieldable(State, self, thread, op);
    }

    pub fn coroutineClose(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return coroutine_mod.coroutineClose(State, self, thread, op);
    }

    pub fn coroutineWrap(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return coroutine_mod.coroutineWrap(State, self, thread, op);
    }

    pub fn callCoroutineWrapper(self: *State, thread: *Thread, op: bytecode.Call, target: *Thread) !void {
        return coroutine_mod.callCoroutineWrapper(State, self, thread, op, target);
    }

    pub fn callCoroutineWrapperWithArgs(self: *State, thread: *Thread, base: u32, return_count: u16, target: *Thread, args: []const Value) !void {
        return coroutine_mod.callCoroutineWrapperWithArgs(State, self, thread, base, return_count, target, args);
    }

    pub fn newCoroutineThread(self: *State, entry: Value) !*Thread {
        return coroutine_mod.newCoroutineThread(State, self, entry);
    }

    pub fn closeCoroutine(self: *State, target: *Thread, error_value: ?Value) !?Value {
        if (target.status == .running and !target.is_main) return self.fail("cannot close a running coroutine");
        return coroutine_mod.closeCoroutine(State, self, target, error_value);
    }

    pub fn resumeCoroutine(self: *State, target: *Thread, args: []const Value) !CoroutineResumeResult {
        return coroutine_mod.resumeCoroutine(State, self, target, args);
    }

    pub fn startCoroutine(self: *State, target: *Thread, args: []const Value) !void {
        return coroutine_mod.startCoroutine(State, self, target, args);
    }

    pub fn callableEntryClosure(self: *State) !*Closure {
        return coroutine_mod.callableEntryClosure(State, self);
    }

    pub fn setCoroutineResumeValues(self: *State, target: *Thread, args: []const Value) !void {
        return coroutine_mod.setCoroutineResumeValues(State, self, target, args);
    }

    pub fn returnCoroutineResumeResult(self: *State, thread: *Thread, base: u32, return_count: u16, result: CoroutineResumeResult) !void {
        return coroutine_mod.returnCoroutineResumeResult(State, self, thread, base, return_count, result);
    }

    pub fn copyValues(self: *State, values: []const Value) ![]Value {
        return coroutine_mod.copyValues(State, self, values);
    }

    pub fn copyStackSlice(self: *State, thread: *Thread, base: usize, count: usize) ![]Value {
        return coroutine_mod.copyStackSlice(State, self, thread, base, count);
    }

    fn lineForErrorLevel(self: *State, thread: *Thread, level: usize) ?usize {
        _ = self;
        if (level == 0 or level > thread.frames.items.len) return null;
        const frame = thread.frames.items[thread.frames.items.len - level];
        return lineForFrame(frame);
    }

    fn sourceForErrorLevel(self: *State, thread: *Thread, level: usize) ?[]const u8 {
        _ = self;
        if (level == 0 or level > thread.frames.items.len) return null;
        const source_name = thread.frames.items[thread.frames.items.len - level].proto.source_name;
        if (source_name.len > 0 and (source_name[0] == '@' or source_name[0] == '=')) return source_name[1..];
        return source_name;
    }

    pub fn collectArgs(self: *State, thread: *Thread, op: bytecode.Call, first: u32) ![]Value {
        return call_mod.collectArgs(State, self, thread, op, first);
    }

    pub fn returnProtectedResult(self: *State, thread: *Thread, base: u32, return_count: u16, result: ProtectedCallResult) !void {
        return call_mod.returnProtectedResult(State, self, thread, base, return_count, result);
    }

    fn rawSet(self: *State, table_value: Value, key_value: Value, value: Value) !void {
        const table = try self.expectTable(table_value);
        const key = try self.writableTableKey(key_value);
        try self.setTableRaw(table, key, value);
        self.writeTableBarrier(table, key, value);
    }

    fn nextValues(self: *State, table_value: Value, key_value: Value) ![2]Value {
        const table = try self.expectTable(table_value);
        const key = try self.readableTableKey(key_value) orelse Value.nil;
        return table.next(key) catch return self.fail("invalid key to 'next'");
    }

    fn callPairsMetamethod(self: *State, thread: *Thread, op: bytecode.Call, metamethod: Value, value: Value) !void {
        const frame_count = thread.frames.items.len;
        const relative_base = thread.scratchRegister();
        const source_base = thread.frames.items[frame_count - 1].base + @as(usize, relative_base);
        try thread.ensureStack(self.allocator, source_base + 4, self.callStackValueLimit(thread));
        thread.stack.items[source_base] = metamethod;
        thread.stack.items[source_base + 1] = value;
        const continuation: types.PairsContinuation = .{
            .frame_count = frame_count,
            .source_base = source_base,
            .base = op.base,
            .return_count = op.return_count,
        };
        // Lua takes four results from __pairs; scratch registers keep padding off locals.
        self.invokeValue(thread, .{ .base = relative_base, .arg_count = 1, .return_count = 4 }, 0) catch |err| {
            if (err == error.CoroutineYield) try self.pushPairsContinuation(thread, continuation);
            return err;
        };
        self.runThreadUntil(thread, frame_count) catch |err| {
            if (err == error.CoroutineYield) try self.pushPairsContinuation(thread, continuation);
            return err;
        };
        try self.returnPairsResults(thread, continuation);
    }

    fn returnPairsResults(self: *State, thread: *Thread, continuation: types.PairsContinuation) !void {
        // Copied because returnValues may resize the stack or overlap the source.
        const values = thread.stack.items[continuation.source_base..][0..4].*;
        try self.returnValues(thread, continuation.base, continuation.return_count, &values);
    }

    fn pushPairsContinuation(self: *State, thread: *Thread, continuation: types.PairsContinuation) !void {
        var pending = continuation;
        thread.continuation_order += 1;
        pending.order = thread.continuation_order;
        try thread.pairs_continuations.append(self.allocator, pending);
        thread.noteContinuation(pending.frame_count);
    }

    fn completeReadyPairsContinuation(self: *State, thread: *Thread) !bool {
        for (thread.pairs_continuations.items, 0..) |continuation, index| {
            if (continuation.frame_count != thread.frames.items.len) continue;
            // A native protected __pairs can suspend at the same depth; finish that inner call first.
            if (readyProtectedContinuationIndex(thread)) |protected_index| {
                if (thread.protected_continuations.items[protected_index].order < continuation.order) {
                    return self.completeReadyProtectedContinuation(thread);
                }
            }
            _ = thread.pairs_continuations.orderedRemove(index);
            thread.refreshContinuationFrameCount();
            try self.returnPairsResults(thread, continuation);
            return true;
        }
        return false;
    }

    fn ipairsIterValues(self: *State, thread: *Thread, table_value: Value, key_value: Value) ![2]Value {
        const current = toInteger(key_value) orelse return self.fail("invalid index to 'ipairs'");
        const next_index = current +% 1;
        const value = try self.getTableFromThread(thread, table_value, .{ .integer = next_index });
        if (value == .nil) return .{ .nil, .nil };
        return .{ .{ .integer = next_index }, value };
    }

    fn iteratorNativeCall(thread: *Thread, op: bytecode.GenericFor) types.NativeCall {
        return nativeCallInfo(thread, .{ .base = op.base, .arg_count = 2, .return_count = 0 }, null, "for iterator", "for iterator", 0);
    }

    fn advanceGenericFor(self: *State, thread: *Thread, op: bytecode.GenericFor, jump_on_nil: bool) !bool {
        const iterator = self.get(thread, op.base);
        const state = self.get(thread, op.base + 1);
        const control = self.get(thread, op.base + 2);
        var fixed: [2]Value = undefined;
        var gmatch_values: stdlib.string.GmatchValues = undefined;
        var owned_values: ?[]Value = null;
        defer if (owned_values) |values| self.allocator.free(values);
        const values: []const Value = switch (iterator) {
            .native_next => blk: {
                if (state != .table) {
                    const previous_native_call = thread.native_call;
                    defer thread.native_call = previous_native_call;
                    thread.native_call = iteratorNativeCall(thread, op);
                    return self.failArgumentType("next", 1, "table", state);
                }
                fixed = try self.nextValues(state, control);
                break :blk fixed[0..2];
            },
            .native_ipairs_iter => blk: {
                // Match invokeValue's native boundary, including __index calls.
                thread.native_call_depth += 1;
                defer thread.native_call_depth -= 1;
                fixed = try self.ipairsIterValues(thread, state, control);
                break :blk fixed[0..2];
            },
            .native => |native| switch (native) {
                .string_gmatch_iter => blk: {
                    gmatch_values = try stdlib.string.gmatchNext(self, state);
                    break :blk gmatch_values.slice();
                },
                .utf8_codes_iter => blk: {
                    const previous_native_call = thread.native_call;
                    defer thread.native_call = previous_native_call;
                    thread.native_call = iteratorNativeCall(thread, op);
                    fixed = try stdlib.utf8.codesNext(self, state, control);
                    break :blk fixed[0..2];
                },
                else => blk: {
                    const args = [_]Value{ state, control };
                    const frame_count = thread.frames.items.len;
                    const previous_name = thread.next_call_name;
                    thread.next_call_name = "for iterator";
                    defer thread.next_call_name = previous_name;
                    owned_values = self.callCollect(thread, iterator, &args) catch |err| switch (err) {
                        error.CoroutineYield => {
                            try self.pushGenericForContinuation(thread, frame_count, op, jump_on_nil);
                            return err;
                        },
                        else => return err,
                    };
                    break :blk owned_values.?;
                },
            },
            else => blk: {
                const args = [_]Value{ state, control };
                const frame_count = thread.frames.items.len;
                const previous_name = thread.next_call_name;
                thread.next_call_name = "for iterator";
                defer thread.next_call_name = previous_name;
                owned_values = self.callCollect(thread, iterator, &args) catch |err| switch (err) {
                    error.CoroutineYield => {
                        try self.pushGenericForContinuation(thread, frame_count, op, jump_on_nil);
                        return err;
                    },
                    else => return err,
                };
                break :blk owned_values.?;
            },
        };
        return self.applyGenericForValues(thread, op, values);
    }

    fn applyGenericForValues(self: *State, thread: *Thread, op: bytecode.GenericFor, values: []const Value) !bool {
        const first_value = if (values.len > 0) values[0] else Value.nil;
        self.set(thread, op.base + 2, first_value);
        for (0..op.variable_count) |index| {
            const value = if (index < values.len) values[index] else Value.nil;
            self.set(thread, op.base + 4 + @as(bytecode.Register, @intCast(index)), value);
        }
        return first_value != .nil;
    }

    fn pushGenericForContinuation(self: *State, thread: *Thread, frame_count: usize, op: bytecode.GenericFor, jump_on_nil: bool) !void {
        try thread.generic_for_continuations.append(self.allocator, .{
            .frame_count = frame_count,
            .op = op,
            .jump_on_nil = jump_on_nil,
        });
        thread.noteContinuation(frame_count);
    }

    fn readyGenericForContinuationIndex(thread: *Thread) ?usize {
        for (thread.generic_for_continuations.items, 0..) |continuation, index| {
            if (continuation.frame_count == thread.frames.items.len) return index;
        }
        return null;
    }

    fn completeReadyGenericForContinuation(self: *State, thread: *Thread) !bool {
        const index = readyGenericForContinuationIndex(thread) orelse return false;
        const continuation = thread.generic_for_continuations.orderedRemove(index);
        thread.refreshContinuationFrameCount();
        const values = try self.copyStackSlice(thread, thread.last_result_base, thread.last_result_count);
        defer self.allocator.free(values);
        if (!(try self.applyGenericForValues(thread, continuation.op, values)) and continuation.jump_on_nil) {
            try self.jumpThread(thread, continuation.op.offset, false);
        }
        return true;
    }

    fn pushTailCallContinuation(self: *State, thread: *Thread, frame_count: usize, base: u32, return_count: u16) !void {
        try thread.tail_call_continuations.append(self.allocator, .{
            .frame_count = frame_count,
            .base = base,
            .return_count = return_count,
        });
        thread.noteContinuation(frame_count);
    }

    fn readyTailCallContinuationIndex(thread: *Thread) ?usize {
        var index = thread.tail_call_continuations.items.len;
        while (index > 0) {
            index -= 1;
            if (thread.tail_call_continuations.items[index].frame_count == thread.frames.items.len) return index;
        }
        return null;
    }

    fn completeReadyTailCallContinuation(self: *State, thread: *Thread) !bool {
        const index = readyTailCallContinuationIndex(thread) orelse return false;
        const continuation = thread.tail_call_continuations.orderedRemove(index);
        thread.refreshContinuationFrameCount();
        try self.returnFromFrame(thread, continuation.base, continuation.return_count);
        return true;
    }

    pub fn expectTable(self: *State, value: Value) !*Table {
        return switch (value) {
            .table => |table| table,
            else => self.fail("table expected"),
        };
    }

    pub fn expectString(self: *State, value: Value) ![]const u8 {
        return switch (value) {
            .string => |string| string,
            else => self.fail("string expected"),
        };
    }

    /// Like `getco` in lcorolib.
    pub fn expectArgumentThread(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !*Thread {
        const value = argValue(self, thread, op, index);
        return switch (value) {
            .thread => |target| target,
            else => self.failArgumentType(function_name, index + 1, "thread", value),
        };
    }

    pub fn expectThread(self: *State, value: Value) !*Thread {
        return switch (value) {
            .thread => |thread| thread,
            else => self.fail("thread expected"),
        };
    }

    fn tableCreateHints(self: *State, thread: *Thread, op: bytecode.Call) ![2]u32 {
        const sizes = [2]i64{
            try self.argumentInteger(thread, op, "table.create", 0),
            try self.optionalArgumentInteger(thread, op, "table.create", 1, 0),
        };
        var hints: [2]u32 = undefined;
        for (sizes, &hints, 1..) |size, *hint, arg_number| {
            if (size < 0 or size > std.math.maxInt(i32)) return self.failArgumentMessage("table.create", @intCast(arg_number), "out of range");
            hint.* = @intCast(size);
        }
        return hints;
    }

    fn callNative(self: *State, native: NativeFn, thread: *Thread, op: bytecode.Call) !void {
        try stdlib.callNative(self, native, thread, op);
    }

    pub fn collectGarbageValue(self: *State, thread: *Thread, op: bytecode.Call) !void {
        return gc_mod.collectGarbageValue(State, self, thread, op);
    }

    pub fn collectGarbageParam(self: *State, value: Value) !GcParam {
        return gc_mod.collectGarbageParam(State, self, value);
    }

    pub fn setGcMode(self: *State, mode: GcMode) GcMode {
        const previous = self.gc_mode;
        if (mode == previous) return previous;
        self.gc_mode = mode;
        if (!self.is_collecting) self.normalizeGcBaseline();
        return previous;
    }

    pub fn stepGc(self: *State, steps: usize) !bool {
        return gc_mod.stepCount(State, self, self.current_thread, steps);
    }

    pub fn normalizeGcBaseline(self: *State) void {
        gc_mod.normalizeBaseline(State, self);
    }

    pub fn collectGarbageStep(self: *State, thread: ?*Thread, budget: i64) !bool {
        return gc_mod.collectGarbageStep(State, self, thread, budget);
    }

    pub fn collectGarbage(self: *State) !void {
        return gc_mod.collectGarbage(State, self);
    }

    pub fn gcParam(self: State, param: GcParam) i64 {
        return gc_mod.gcParam(State, self, param);
    }

    pub fn setGcParam(self: *State, param: GcParam, value: i64) void {
        return gc_mod.setGcParam(State, self, param, value);
    }

    pub fn collectGarbageConservatively(self: *State, thread: ?*Thread) !void {
        return gc_mod.collectGarbageConservatively(State, self, thread);
    }

    pub fn collectGarbageWithFinalizers(self: *State, thread: ?*Thread) !void {
        return gc_mod.collectGarbageWithFinalizers(State, self, thread);
    }

    pub fn collectGarbageWithFinalizersMode(self: *State, thread: ?*Thread, mark_all_stack_registers: bool) !void {
        return gc_mod.collectGarbageWithFinalizersMode(State, self, thread, mark_all_stack_registers);
    }

    pub fn shouldRunAutoGc(self: *State) bool {
        return gc_mod.shouldRunAutoGc(State, self);
    }

    pub fn resetAutoGcThreshold(self: *State) void {
        return gc_mod.resetAutoGcThreshold(State, self);
    }

    pub fn resetMarks(self: *State) void {
        return gc_mod.resetMarks(State, self);
    }

    pub fn markRoots(self: *State) void {
        return gc_mod.markRoots(State, self);
    }

    pub fn markValue(self: *State, value: Value) void {
        return gc_mod.markValue(State, self, value);
    }

    pub fn markRuntimeErrorPayload(self: *State, payload: ?RuntimeErrorPayload) void {
        return gc_mod.markRuntimeErrorPayload(State, self, payload);
    }

    pub fn markString(self: *State, bytes: []const u8) void {
        return gc_mod.markString(State, self, bytes);
    }

    pub fn markTable(self: *State, table: *Table) void {
        return gc_mod.markTable(State, self, table);
    }

    pub fn markUserdata(self: *State, userdata: *Userdata) void {
        return gc_mod.markUserdata(State, self, userdata);
    }

    pub fn markWeakTableStrings(self: *State, table: *Table, keys: bool, values: bool) void {
        return gc_mod.markWeakTableStrings(State, self, table, keys, values);
    }

    pub fn markWeakString(self: *State, value: Value) void {
        return gc_mod.markWeakString(State, self, value);
    }

    pub fn markClosure(self: *State, closure: *Closure) void {
        return gc_mod.markClosure(State, self, closure);
    }

    pub fn markUpvalue(self: *State, upvalue: *Upvalue) void {
        return gc_mod.markUpvalue(State, self, upvalue);
    }

    pub fn markThread(self: *State, thread: *Thread) void {
        return gc_mod.markThread(State, self, thread);
    }

    pub fn markThreadStack(self: *State, thread: *Thread) void {
        return gc_mod.markThreadStack(State, self, thread);
    }

    pub fn markStackRange(self: *State, thread: *Thread, base: usize, count: usize) void {
        return gc_mod.markStackRange(State, self, thread, base, count);
    }

    pub fn weakMode(self: *State, table: *Table) WeakMode {
        return gc_mod.weakMode(State, self, table);
    }

    pub fn hasWeakTables(self: *State) bool {
        return gc_mod.hasWeakTables(State, self);
    }

    pub fn markEphemeronValues(self: *State, table: *Table) bool {
        return gc_mod.markEphemeronValues(State, self, table);
    }

    pub fn convergeEphemerons(self: *State) void {
        return gc_mod.convergeEphemerons(State, self);
    }

    pub fn markValueChanged(self: *State, value: Value) bool {
        return gc_mod.markValueChanged(State, self, value);
    }

    pub fn valueIsMarked(self: *State, value: Value) bool {
        return gc_mod.valueIsMarked(State, self, value);
    }

    pub fn valueIsWeaklyCleared(self: *State, value: Value) bool {
        return gc_mod.valueIsWeaklyCleared(State, self, value);
    }

    pub fn valueIsCollectableUnmarked(self: *State, value: Value) bool {
        return gc_mod.valueIsCollectableUnmarked(State, self, value);
    }

    pub fn clearWeakValues(self: *State) void {
        return gc_mod.clearWeakValues(State, self);
    }

    pub fn clearWeakTables(self: *State) void {
        return gc_mod.clearWeakTables(State, self);
    }

    pub fn clearDeadHashKeys(self: *State) void {
        return gc_mod.clearDeadHashKeys(State, self);
    }

    pub fn clearWeakTableValues(self: *State, table: *Table) void {
        return gc_mod.clearWeakTableValues(State, self, table);
    }

    pub fn clearWeakTableKeys(self: *State, table: *Table) void {
        return gc_mod.clearWeakTableKeys(State, self, table);
    }

    pub fn writeTableBarrier(self: *State, table: *Table, key: Value, value: Value) void {
        return gc_mod.writeTableBarrier(State, self, table, key, value);
    }

    pub fn upvalueBarrier(self: *State, closure: *Closure, upvalue: *Upvalue) void {
        gc_mod.rememberObject(State, self, .{ .closure = closure });
        if (self.gc_phase != .pause) self.markUpvalue(upvalue);
    }

    pub fn threadBarrier(self: *State, thread: *Thread, value: Value) void {
        gc_mod.syncThreadStorage(State, self, thread);
        gc_mod.rememberObject(State, self, .{ .thread = thread });
        self.markValue(value);
    }

    pub fn writeBarrier(self: *State, parent: anytype, child: Value) void {
        return gc_mod.writeBarrier(State, self, parent, child);
    }

    /// Runs pending finalizers as `deinit` does, keeping the state. Only for an idle host;
    /// later registrations are left for `deinit`.
    pub fn runCloseFinalizers(self: *State) void {
        if (self.execution_depth != 0 or self.current_thread != null) return;
        if (self.table_pending_finalizer_head == null and self.table_finalizer_head == null and !gc_mod.hasUserdataLuaFinalizers(State, self) and !stdlib.io.hasOpenFiles(self)) return;
        var proto = proto_mod.Proto.init(self.allocator);
        defer proto.deinit();
        proto.source_name = "=[C]";
        var closure = Closure{ .proto = &proto, .upvalues = &.{} };
        const thread = self.newHostThread(&closure) catch return;
        defer self.retireHostThread(thread);
        self.current_thread = thread;
        defer self.current_thread = null;
        gc_mod.runCloseFinalizers(State, self, thread);
    }

    pub fn runFinalizersFromHost(self: *State, limit: usize) anyerror!bool {
        var proto = proto_mod.Proto.init(self.allocator);
        defer proto.deinit();
        proto.source_name = "=[C]";
        var closure = Closure{ .proto = &proto, .upvalues = &.{} };
        const thread = try self.newHostThread(&closure);
        defer self.retireHostThread(thread);
        const previous_thread = self.current_thread;
        self.current_thread = thread;
        defer self.current_thread = previous_thread;
        return gc_mod.runFinalizerBatch(State, self, thread, limit);
    }

    pub fn runPendingFinalizers(self: *State, thread: ?*Thread) !void {
        return gc_mod.runPendingFinalizers(State, self, thread);
    }

    pub fn runPendingUserdataFinalizers(self: *State) !void {
        return gc_mod.runPendingUserdataFinalizers(State, self);
    }

    pub fn callableValue(self: *State, value: Value) bool {
        return gc_mod.callableValue(State, self, value);
    }

    pub fn sweepStrings(self: *State) void {
        return gc_mod.sweepStrings(State, self);
    }

    pub fn sweepUserdata(self: *State) void {
        return gc_mod.sweepUserdata(State, self);
    }

    pub fn sweepTables(self: *State) void {
        return gc_mod.sweepTables(State, self);
    }

    pub fn sweepClosures(self: *State) void {
        return gc_mod.sweepClosures(State, self);
    }

    pub fn sweepUpvalues(self: *State) void {
        return gc_mod.sweepUpvalues(State, self);
    }

    pub fn sweepThreads(self: *State) void {
        return gc_mod.sweepThreads(State, self);
    }

    pub fn findStringAllocation(self: *State, bytes: []const u8) ?usize {
        return gc_mod.findStringAllocation(State, self, bytes);
    }

    pub fn isTrackedThread(self: *State, thread: *Thread) bool {
        return gc_mod.isTrackedThread(State, self, thread);
    }

    pub fn isTrackedTable(self: *State, table: *Table) bool {
        return gc_mod.isTrackedTable(State, self, table);
    }

    pub fn isTrackedUserdata(self: *State, userdata: *Userdata) bool {
        return gc_mod.isTrackedUserdata(State, self, userdata);
    }

    pub fn isTrackedClosure(self: *State, closure: *Closure) bool {
        return gc_mod.isTrackedClosure(State, self, closure);
    }

    pub fn isTrackedUpvalue(self: *State, upvalue: *Upvalue) bool {
        return gc_mod.isTrackedUpvalue(State, self, upvalue);
    }

    pub fn destroyTable(self: *State, table: *Table) void {
        return gc_mod.destroyTable(State, self, table);
    }

    pub fn destroyUserdata(self: *State, userdata: *Userdata) void {
        return gc_mod.destroyUserdata(State, self, userdata);
    }

    pub fn destroyClosure(self: *State, closure: *Closure) void {
        return gc_mod.destroyClosure(State, self, closure);
    }

    pub fn destroyThread(self: *State, thread: *Thread) void {
        return gc_mod.destroyThread(State, self, thread);
    }

    pub fn allocationStats(self: State) RuntimeAllocationStats {
        return gc_mod.allocationStats(State, self);
    }

    fn appendUnhandledErrorDebugDump(self: *State, thread: *Thread, err: anyerror) !void {
        return debug_mod.appendUnhandledErrorDebugDump(State, self, thread, err);
    }

    fn appendDebugFrames(self: *State, out: *std.ArrayList(u8), thread: *Thread) !void {
        return debug_mod.appendDebugFrames(State, self, out, thread);
    }

    fn appendDebugLocals(self: *State, out: *std.ArrayList(u8), thread: *Thread, frame: CallFrame) !void {
        return debug_mod.appendDebugLocals(State, self, out, thread, frame);
    }

    fn appendDebugVarargs(self: *State, out: *std.ArrayList(u8), frame: CallFrame) !void {
        return debug_mod.appendDebugVarargs(State, self, out, frame);
    }

    fn appendDebugUpvalues(self: *State, out: *std.ArrayList(u8), frame: CallFrame) !void {
        return debug_mod.appendDebugUpvalues(State, self, out, frame);
    }

    fn appendDebugStack(self: *State, out: *std.ArrayList(u8), thread: *Thread) !void {
        return debug_mod.appendDebugStack(State, self, out, thread);
    }

    fn appendDebugValue(self: *State, out: *std.ArrayList(u8), value: Value) !void {
        return debug_mod.appendDebugValue(State, self, out, value);
    }

    pub fn failRuntimeDetail(self: *State, thread: ?*Thread, detail: []const u8) RuntimeError {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        self.appendRuntimeErrorPrefix(&out, thread) catch return self.fail(detail);
        out.appendSlice(self.allocator, detail) catch return self.fail(detail);
        return self.fail(self.intern(out.items) catch return self.fail(detail));
    }

    fn failDivisionByZero(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: BinaryOp) RuntimeError {
        const message = if (op == .mod) "attempt to perform 'n%0'" else "attempt to divide by zero";
        if (lhs == .string or rhs == .string) return self.fail(message);
        return self.failRuntimeDetail(thread, message);
    }

    fn failNoIntegerRepresentation(self: *State, thread: *Thread, lhs: Value) RuntimeError {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        const operand_index: usize = if (toBitwiseInteger(lhs) == null) 0 else 1;
        detail.appendSlice(self.allocator, "number") catch return self.fail("number has no integer representation");
        self.appendSiteOrigin(&detail, self.currentErrorSite(thread), operand_index, false) catch return self.fail("number has no integer representation");
        detail.appendSlice(self.allocator, " has no integer representation") catch return self.fail("number has no integer representation");
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn failBinaryTypeError(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: BinaryOp) RuntimeError {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        const site = self.currentErrorSite(thread);
        switch (op) {
            .add, .sub, .mul, .div, .idiv, .mod, .pow => {
                if (lhs == .string or rhs == .string) {
                    appendFmt(self.allocator, &detail, "attempt to {s} a '{s}' with a '{s}'", .{ arithmeticVerb(op), luaTypeName(lhs), luaTypeName(rhs) }) catch return self.fail("attempt to perform operation on unsupported values");
                    return self.failRuntimeDetail(thread, detail.items);
                }
                const operand_index: usize = if (toNumberMaybe(lhs) == null) 0 else 1;
                const bad_value = if (operand_index == 0) lhs else rhs;
                appendFmt(self.allocator, &detail, "attempt to perform arithmetic on a {s} value", .{self.luaTypeNameForError(bad_value)}) catch return self.fail("attempt to perform operation on unsupported values");
                self.appendSiteOrigin(&detail, site, operand_index, false) catch return self.fail("attempt to perform operation on unsupported values");
            },
            .band, .bor, .bxor, .shl, .shr => {
                if (isNumber(lhs) and isNumber(rhs)) return self.failNoIntegerRepresentation(thread, lhs);
                const operand_index: usize = if (!isNumber(lhs)) 0 else 1;
                const bad_value = if (operand_index == 0) lhs else rhs;
                appendFmt(self.allocator, &detail, "attempt to perform bitwise operation on a {s} value", .{self.luaTypeNameForError(bad_value)}) catch return self.fail("attempt to perform operation on unsupported values");
                self.appendSiteOrigin(&detail, site, operand_index, true) catch return self.fail("attempt to perform operation on unsupported values");
            },
            .concat => {
                const operand_index: usize = if (!luaStringLike(lhs)) 0 else 1;
                const bad_value = if (operand_index == 0) lhs else rhs;
                appendFmt(self.allocator, &detail, "attempt to concatenate a {s} value", .{self.luaTypeNameForError(bad_value)}) catch return self.fail("attempt to perform operation on unsupported values");
                self.appendSiteOrigin(&detail, site, operand_index, false) catch return self.fail("attempt to perform operation on unsupported values");
            },
        }
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn failConcatRangeTypeError(self: *State, thread: *Thread, lhs: Value, rhs: Value, lhs_index: usize) RuntimeError {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        const operand_index = if (!luaStringLike(lhs)) lhs_index else lhs_index + 1;
        const bad_value = if (!luaStringLike(lhs)) lhs else rhs;
        appendFmt(self.allocator, &detail, "attempt to concatenate a {s} value", .{self.luaTypeNameForError(bad_value)}) catch return self.fail("attempt to perform operation on unsupported values");
        self.appendSiteOrigin(&detail, self.currentErrorSite(thread), operand_index, true) catch return self.fail("attempt to perform operation on unsupported values");
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn failUnaryTypeError(self: *State, thread: *Thread, value: Value, op: UnaryMetamethodOp) RuntimeError {
        if (op == .bnot and isNumber(value)) return self.failNoIntegerRepresentation(thread, value);
        if (op == .unm and value == .string) return self.failRuntimeDetail(thread, "attempt to unm a 'string' with a 'string'");
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        const operation = switch (op) {
            .unm => "arithmetic",
            .bnot => "bitwise operation",
        };
        appendFmt(self.allocator, &detail, "attempt to perform {s} on a {s} value", .{ operation, self.luaTypeNameForError(value) }) catch return self.fail("attempt to perform operation on unsupported value");
        self.appendSiteOrigin(&detail, self.currentErrorSite(thread), 0, op == .bnot) catch return self.fail("attempt to perform operation on unsupported value");
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn failCompareTypeError(self: *State, thread: *Thread, lhs: Value, rhs: Value) RuntimeError {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        const lhs_type = self.luaTypeNameForError(lhs);
        const rhs_type = self.luaTypeNameForError(rhs);
        if (std.mem.eql(u8, lhs_type, rhs_type)) {
            appendFmt(self.allocator, &detail, "attempt to compare two {s} values", .{lhs_type}) catch return self.fail("attempt to compare unsupported values");
        } else {
            appendFmt(self.allocator, &detail, "attempt to compare {s} with {s}", .{ lhs_type, rhs_type }) catch return self.fail("attempt to compare unsupported values");
        }
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn failLengthTypeError(self: *State, thread: *Thread, value: Value) RuntimeError {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        appendFmt(self.allocator, &detail, "attempt to get length of a {s} value", .{self.luaTypeNameForError(value)}) catch return self.fail("attempt to get length of a non-string value");
        self.appendSiteOrigin(&detail, self.currentErrorSite(thread), 0, false) catch return self.fail("attempt to get length of a non-string value");
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn failIndexTypeError(self: *State, thread: ?*Thread, value: Value) RuntimeError {
        return self.failAccessTypeError(thread, value, indexErrorMessage(value));
    }

    fn failNewIndexTypeError(self: *State, thread: ?*Thread, value: Value) RuntimeError {
        return self.failAccessTypeError(thread, value, indexErrorMessage(value));
    }

    fn failCallTypeError(self: *State, thread: *Thread, value: Value, call_name: ?[]const u8, call_namewhat: ?[]const u8) RuntimeError {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        appendFmt(self.allocator, &detail, "attempt to call a {s} value", .{self.luaTypeNameForError(value)}) catch return self.fail(callErrorMessage(value));
        if (call_name != null and call_namewhat != null and std.mem.eql(u8, call_namewhat.?, "metamethod")) {
            appendFmt(self.allocator, &detail, " (metamethod '{s}')", .{call_name.?}) catch return self.fail(callErrorMessage(value));
        } else {
            self.appendCallOrigin(&detail, self.currentErrorSite(thread)) catch return self.fail(callErrorMessage(value));
        }
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn failAccessTypeError(self: *State, thread: ?*Thread, value: Value, fallback: []const u8) RuntimeError {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        appendFmt(self.allocator, &detail, "attempt to index a {s} value", .{self.luaTypeNameForError(value)}) catch return self.fail(fallback);
        const site = if (thread) |active| self.currentErrorSite(active) else null;
        self.appendSiteOrigin(&detail, site, 0, false) catch return self.fail(fallback);
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn failForTypeError(self: *State, thread: *Thread, which: ForValueKind, value: Value) RuntimeError {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(self.allocator);
        appendFmt(self.allocator, &detail, "bad 'for' {s} (number expected, got {s})", .{ forValueName(which), self.luaTypeNameForError(value) }) catch return self.fail("bad 'for' value");
        return self.failRuntimeDetail(thread, detail.items);
    }

    fn appendRuntimeErrorPrefix(self: *State, out: *std.ArrayList(u8), thread: ?*Thread) !void {
        const active = thread orelse return;
        if (active.frames.items.len == 0) return;
        if (activeNativeCall(active) != null) return;
        if (active.frames.items[active.frames.items.len - 1].closure.stripped_debug) {
            try out.appendSlice(self.allocator, "?:?: ");
            return;
        }
        const site = self.currentErrorSite(active) orelse return;
        const frame = active.frames.items[active.frames.items.len - 1];
        try appendFmt(self.allocator, out, "{s}:{d}: ", .{ runtimeSourceName(frame.proto.source_name), site.line });
    }

    fn currentErrorSite(self: *State, thread: *Thread) ?proto_mod.ErrorSite {
        if (activeNativeCall(thread) != null) return null;
        return self.instructionErrorSite(thread);
    }

    fn instructionErrorSite(self: *State, thread: *Thread) ?proto_mod.ErrorSite {
        _ = self;
        if (thread.frames.items.len == 0) return null;
        const frame = thread.frames.items[thread.frames.items.len - 1];
        if (frame.closure.stripped_debug) return null;
        if (frame.pc == 0) return null;
        return frame.proto.errorSiteAt(frame.pc - 1) orelse blk: {
            if (frame.proto.line_info.items.len == 0) return null;
            const pc = @min(frame.pc - 1, frame.proto.line_info.items.len - 1);
            break :blk proto_mod.ErrorSite{ .line = frame.proto.line_info.items[pc].line, .op = .call };
        };
    }

    fn appendSiteOrigin(self: *State, out: *std.ArrayList(u8), site: ?proto_mod.ErrorSite, operand_index: usize, allow_constant: bool) !void {
        const active_site = site orelse return;
        if (operand_index >= active_site.operands.len) return;
        try self.appendOrigin(out, active_site.operands[operand_index], allow_constant);
    }

    fn appendCallOrigin(self: *State, out: *std.ArrayList(u8), site: ?proto_mod.ErrorSite) !void {
        const active_site = site orelse return;
        if (active_site.call_name) |origin| return self.appendOrigin(out, origin, false);
        if (active_site.operands.len != 0) return self.appendOrigin(out, active_site.operands[0], false);
    }

    fn appendOrigin(self: *State, out: *std.ArrayList(u8), origin: proto_mod.OperandOrigin, allow_constant: bool) !void {
        switch (origin) {
            .temporary => {},
            .local => |name| try appendFmt(self.allocator, out, " (local '{s}')", .{name}),
            .upvalue => |name| try appendFmt(self.allocator, out, " (upvalue '{s}')", .{name}),
            .global => |name| try appendFmt(self.allocator, out, " (global '{s}')", .{name}),
            .field => |name| try appendFmt(self.allocator, out, " (field '{s}')", .{name}),
            .method => |name| try appendFmt(self.allocator, out, " (method '{s}')", .{name}),
            .metamethod => |name| try appendFmt(self.allocator, out, " (metamethod '{s}')", .{name}),
            .constant => |value| if (allow_constant) try appendFmt(self.allocator, out, " (constant '{s}')", .{value}),
        }
    }

    pub fn errorDetailAlloc(self: *State, allocator: std.mem.Allocator, err: anyerror) ![]const u8 {
        if (self.last_error == null) return allocator.dupe(u8, @errorName(err));
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        try appendErrorValue(allocator, &out, self.currentErrorValue());
        return allocator.dupe(u8, out.items);
    }

    pub fn fail(self: *State, message: []const u8) RuntimeError {
        self.last_error = .{ .diagnostic = message };
        self.error_handled = false;
        return error.RuntimeError;
    }

    /// Like `luaL_argerror`; `index` is 1-based and `function_name` is the fallback name.
    pub fn failArgument(self: *State, function_name: []const u8, index: u32, detail: errors.ArgumentErrorDetail) RuntimeError {
        self.error_handled = false;
        const rendered = self.renderArgumentError(function_name, index, detail) catch {
            self.last_error = .{ .argument = .{ .function_name = function_name, .index = index, .detail = detail } };
            return error.RuntimeError;
        };
        self.last_error = .{ .diagnostic = rendered };
        return error.RuntimeError;
    }

    pub fn failArgumentMessage(self: *State, function_name: []const u8, index: u32, message: []const u8) RuntimeError {
        return self.failArgument(function_name, index, .{ .message = message });
    }

    pub fn failArgumentType(self: *State, function_name: []const u8, index: u32, expected: []const u8, actual: Value) RuntimeError {
        return self.failArgument(function_name, index, .{ .expected = .{
            .expected = expected,
            .actual = self.luaTypeNameForError(actual),
        } });
    }

    /// Like `luaL_error`: prefixes the calling Lua code's position.
    pub fn failLibrary(self: *State, message: []const u8) RuntimeError {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        self.appendLibraryWhere(&out) catch return self.fail(message);
        if (out.items.len == 0) return self.fail(message);
        out.appendSlice(self.allocator, message) catch return self.fail(message);
        return self.fail(self.intern(out.items) catch return self.fail(message));
    }

    /// Prefixes a string error with `luaL_where(L, 1)`, as `coroutine.wrap` does.
    pub fn withLibraryWhere(self: *State, value: Value) !Value {
        if (value != .string) return value;
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        try self.appendLibraryWhere(&out);
        if (out.items.len == 0) return value;
        try out.appendSlice(self.allocator, value.string);
        return .{ .string = try self.intern(out.items) };
    }

    pub fn failLibraryFmt(self: *State, comptime fmt: []const u8, args: anytype) RuntimeError {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        appendFmt(self.allocator, &out, fmt, args) catch return self.fail(fmt);
        const message = self.intern(out.items) catch return self.fail(fmt);
        return self.failLibrary(message);
    }

    fn activeNativeCall(thread: *Thread) ?types.NativeCall {
        const call = thread.native_call orelse return null;
        if (call.frame_count == 0 or thread.frames.items.len != call.frame_count) return null;
        return call;
    }

    fn appendLibraryWhere(self: *State, out: *std.ArrayList(u8)) !void {
        const thread = self.current_thread orelse return;
        const call = activeNativeCall(thread) orelse return;
        if (calledFromNative(thread, call)) return;
        const frame = thread.frames.items[thread.frames.items.len - 1];
        if (frame.closure.stripped_debug or debug_mod.isCoroutineEntryFrame(frame)) return;
        const site = self.instructionErrorSite(thread) orelse return;
        try appendFmt(self.allocator, out, "{s}:{d}: ", .{ runtimeSourceName(frame.proto.source_name), site.line });
    }

    const CallName = struct { name: []const u8, namewhat: []const u8 };

    /// Also true for a metamethod the `ipairs` iterator called during a generic-for step.
    fn calledFromNative(thread: *Thread, call: types.NativeCall) bool {
        if (call.from_native) return true;
        const namewhat = call.namewhat orelse return false;
        if (!std.mem.eql(u8, namewhat, "metamethod")) return false;
        const frame = thread.frames.items[thread.frames.items.len - 1];
        if (frame.pc == 0 or frame.pc > frame.proto.instructions.items.len) return false;
        return switch (frame.proto.instructions.items[frame.pc - 1]) {
            .tfor_prep, .tfor_call => true,
            else => false,
        };
    }

    fn nativeCallName(self: *State, thread: *Thread, call: types.NativeCall) ?CallName {
        if (calledFromNative(thread, call)) return null;
        if (call.name) |name| {
            if (call.namewhat) |namewhat| return .{ .name = name, .namewhat = namewhat };
            if (std.mem.eql(u8, name, "for iterator")) return .{ .name = name, .namewhat = name };
            return .{ .name = name, .namewhat = "metamethod" };
        }
        const frame = thread.frames.items[thread.frames.items.len - 1];
        if (call.base >= frame.proto.max_registers) return null;
        const site = self.instructionErrorSite(thread) orelse return null;
        const origin = site.call_name orelse return null;
        return switch (origin) {
            .temporary => null,
            .local => |name| .{ .name = name, .namewhat = "local" },
            .upvalue => |name| .{ .name = name, .namewhat = "upvalue" },
            .global => |name| .{ .name = name, .namewhat = "global" },
            .field => |name| .{ .name = name, .namewhat = "field" },
            .method => |name| .{ .name = name, .namewhat = "method" },
            .metamethod => |name| .{ .name = name, .namewhat = "metamethod" },
            .constant => |name| .{ .name = name, .namewhat = "constant" },
        };
    }

    /// Like `pushglobalfuncname`.
    pub fn appendGlobalFunctionName(self: *State, out: *std.ArrayList(u8), callee: Value) !bool {
        const globals = self.global_table orelse return false;
        if (findFunctionField(globals, callee)) |key| {
            try out.appendSlice(self.allocator, key);
            return true;
        }
        const package = globals.get(.{ .string = "package" });
        const loaded = if (package == .table) package.table.get(.{ .string = "loaded" }) else Value.nil;
        const modules = if (loaded == .table) loaded.table else globals;
        for (modules.entries.items) |entry| {
            if (entry.key != .string or entry.value != .table or entry.value.table == globals) continue;
            if (findFunctionField(entry.value.table, callee)) |key| {
                try appendFmt(self.allocator, out, "{s}.{s}", .{ entry.key.string, key });
                return true;
            }
        }
        return false;
    }

    fn findFunctionField(table: *Table, callee: Value) ?[]const u8 {
        for (table.entries.items) |entry| {
            if (entry.key == .string and valuesEqual(entry.value, callee)) return entry.key.string;
        }
        return null;
    }

    fn renderArgumentError(self: *State, function_name: []const u8, raw_index: u32, detail: errors.ArgumentErrorDetail) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        const thread = self.current_thread;
        const call: ?types.NativeCall = if (thread) |active| activeNativeCall(active) else null;

        var actual_detail = detail;
        if (call) |native| switch (actual_detail) {
            .expected => |*expected| if (raw_index > native.arg_count and std.mem.eql(u8, expected.actual, "nil")) {
                expected.actual = "no value";
            },
            .message => {},
        };

        try self.appendLibraryWhere(&out);
        var index = raw_index;
        const name: ?CallName = if (call) |native| self.nativeCallName(thread.?, native) else null;
        const extra_args: u32 = if (call) |native| native.extra_args else 0;
        const argword = if (index <= extra_args) "extra argument" else "argument";
        if (index > extra_args) {
            index -= extra_args;
            if (name) |known| if (std.mem.eql(u8, known.namewhat, "method")) {
                index -|= 1;
                if (index == 0) {
                    try appendFmt(self.allocator, &out, "calling '{s}' on bad self (", .{known.name});
                    try appendArgumentDetail(self.allocator, &out, actual_detail);
                    try out.append(self.allocator, ')');
                    return self.intern(out.items);
                }
            };
        }
        try appendFmt(self.allocator, &out, "bad {s} #{d} to '", .{ argword, index });
        if (name) |known| {
            try out.appendSlice(self.allocator, known.name);
        } else {
            var fallback = function_name;
            if (call) |native| {
                const active = thread.?;
                const frame = active.frames.items[native.frame_count - 1];
                const callee = active.stack.items[frame.base + native.base];
                if (try self.appendGlobalFunctionName(&out, callee)) {
                    fallback = "";
                } else if (callee != .api_callback) {
                    fallback = "?";
                }
            }
            try out.appendSlice(self.allocator, fallback);
        }
        try out.appendSlice(self.allocator, "' (");
        try appendArgumentDetail(self.allocator, &out, actual_detail);
        try out.append(self.allocator, ')');
        return self.intern(out.items);
    }

    fn appendArgumentDetail(allocator: std.mem.Allocator, out: *std.ArrayList(u8), detail: errors.ArgumentErrorDetail) !void {
        switch (detail) {
            .message => |message| try out.appendSlice(allocator, message),
            .expected => |expected| try appendFmt(allocator, out, "{s} expected, got {s}", .{ expected.expected, expected.actual }),
        }
    }

    /// Like `luaL_checklstring`; numbers are converted in place, keeping the string reachable.
    pub fn expectArgumentString(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) ![]const u8 {
        const value = argValue(self, thread, op, index);
        return switch (value) {
            .string => |string| string,
            .integer, .number => {
                var buffer: [value_mod.max_number_text_len]u8 = undefined;
                const string = try self.intern(value_mod.formatNumber(&buffer, value));
                const frame = thread.frames.items[thread.frames.items.len - 1];
                thread.stack.items[frame.base + op.base + 1 + index] = .{ .string = string };
                return string;
            },
            else => self.failArgumentType(function_name, index + 1, "string", value),
        };
    }

    pub fn optionalArgumentString(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !?[]const u8 {
        if (argValue(self, thread, op, index) == .nil) return null;
        return try self.expectArgumentString(thread, op, function_name, index);
    }

    pub fn expectArgumentTable(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !*Table {
        const value = argValue(self, thread, op, index);
        return switch (value) {
            .table => |table| table,
            else => self.failArgumentType(function_name, index + 1, "table", value),
        };
    }

    pub fn argumentNumber(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !f64 {
        const value = argValue(self, thread, op, index);
        return toNumberMaybe(value) orelse self.failArgumentType(function_name, index + 1, "number", value);
    }

    pub fn optionalArgumentInteger(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32, default: i64) !i64 {
        if (argValue(self, thread, op, index) == .nil) return default;
        return self.argumentInteger(thread, op, function_name, index);
    }

    pub fn argumentInteger(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !i64 {
        const value = argValue(self, thread, op, index);
        if (toInteger(value)) |integer| return integer;
        const number = toNumberMaybe(value) orelse return self.failArgumentType(function_name, index + 1, "number", value);
        return floatToInteger(number) orelse self.failArgumentMessage(function_name, index + 1, "number has no integer representation");
    }

    fn failLoadDiagnostic(self: *State, source_name: ?[]const u8, source_text: []const u8, diagnostic: ?errors.Diagnostic, fallback: []const u8) RuntimeError {
        const rendered = if (diagnostic) |diag|
            errors.renderLoadDiagnostic(self.allocator, source_name, source_text, diag) catch return self.fail(fallback)
        else
            return self.fail(fallback);
        defer self.allocator.free(rendered);
        return self.fail(self.intern(rendered) catch return self.fail(fallback));
    }

    pub fn failValue(self: *State, value: Value) RuntimeError {
        self.last_error = .{ .lua_value = value };
        self.error_handled = false;
        return error.RuntimeError;
    }

    pub fn throwValue(self: *State, value: Value) RuntimeError {
        return self.failValue(value);
    }

    /// For an error that already went through its message handler.
    pub fn rethrowValue(self: *State, value: Value) RuntimeError {
        self.last_error = .{ .lua_value = value };
        self.error_handled = true;
        return error.RuntimeError;
    }

    pub fn currentErrorValue(self: *State) Value {
        const payload = self.last_error orelse return .nil;
        return payload.luaValue(self);
    }
};

const BinaryOp = enum { add, sub, mul, div, idiv, mod, pow, band, bor, bxor, shl, shr, concat };
const UnaryMetamethodOp = enum { unm, bnot };
pub const CompareOp = enum { lt, le };
const ForValueKind = enum { initial, limit, step };

fn arithmeticVerb(op: BinaryOp) []const u8 {
    return switch (op) {
        .add => "add",
        .sub => "sub",
        .mul => "mul",
        .div => "div",
        .idiv => "idiv",
        .mod => "mod",
        .pow => "pow",
        else => "perform arithmetic on",
    };
}

fn forValueName(kind: ForValueKind) []const u8 {
    return switch (kind) {
        .initial => "initial value",
        .limit => "limit",
        .step => "step",
    };
}

pub fn luaTypeName(value: Value) []const u8 {
    return switch (value) {
        .nil => "nil",
        .boolean => "boolean",
        .integer, .number => "number",
        .string => "string",
        .table => "table",
        .userdata => "userdata",
        .thread => "thread",
        .closure,
        .coroutine_wrapper,
        .gmatch_iterator,
        .native_print,
        .native_tostring,
        .native_getmetatable,
        .native_setmetatable,
        .native_rawequal,
        .native_rawget,
        .native_rawset,
        .native_rawlen,
        .native_next,
        .native_pairs,
        .native_ipairs,
        .native_ipairs_iter,
        .native_table_create,
        .native_select,
        .native_assert,
        .native_error,
        .native_pcall,
        .native_xpcall,
        .native_collectgarbage,
        .native_debug_traceback,
        .native_coroutine_create,
        .native_coroutine_resume,
        .native_coroutine_yield,
        .native_coroutine_status,
        .native_coroutine_running,
        .native_coroutine_isyieldable,
        .native_coroutine_close,
        .native_coroutine_wrap,
        .native,
        .api_callback,
        => "function",
    };
}

fn runtimeSourceName(name: []const u8) []const u8 {
    if (name.len > 0 and (name[0] == '@' or name[0] == '=')) return name[1..];
    return name;
}

fn rawBinaryOp(lhs: Value, rhs: Value, op: BinaryOp) !?Value {
    switch (op) {
        .add, .sub, .mul, .idiv, .mod => {
            if (lhs == .integer and rhs == .integer) {
                return switch (op) {
                    .add => .{ .integer = lhs.integer +% rhs.integer },
                    .sub => .{ .integer = lhs.integer -% rhs.integer },
                    .mul => .{ .integer = lhs.integer *% rhs.integer },
                    .idiv => if (rhs.integer == 0) error.RuntimeError else .{ .integer = floorDiv(lhs.integer, rhs.integer) },
                    .mod => if (rhs.integer == 0) error.RuntimeError else .{ .integer = floorMod(lhs.integer, rhs.integer) },
                    else => unreachable,
                };
            }
            if (toInteger(lhs)) |left| {
                if (toInteger(rhs)) |right| {
                    return switch (op) {
                        .add => .{ .integer = left +% right },
                        .sub => .{ .integer = left -% right },
                        .mul => .{ .integer = left *% right },
                        .idiv => if (right == 0) error.RuntimeError else .{ .integer = floorDiv(left, right) },
                        .mod => if (right == 0) error.RuntimeError else .{ .integer = floorMod(left, right) },
                        else => unreachable,
                    };
                }
            }
        },
        .band, .bor, .bxor, .shl, .shr => {
            if (toBitwiseInteger(lhs)) |left| {
                if (toBitwiseInteger(rhs)) |right| {
                    return .{ .integer = rawBitwise(left, right, op) };
                }
            }
        },
        .div, .pow, .concat => {},
    }

    if (op == .concat) return null;
    const left = toNumberMaybe(lhs) orelse return null;
    const right = toNumberMaybe(rhs) orelse return null;
    return switch (op) {
        .add => .{ .number = left + right },
        .sub => .{ .number = left - right },
        .mul => .{ .number = left * right },
        .div => .{ .number = left / right },
        .idiv => .{ .number = @floor(left / right) },
        .mod => .{ .number = floorModNumber(left, right) },
        .pow => .{ .number = std.math.pow(f64, left, right) },
        else => null,
    };
}

inline fn rawNumericBinaryOpFast(lhs: Value, rhs: Value, comptime op: BinaryOp) ?Value {
    return switch (lhs) {
        .integer => |left_integer| switch (rhs) {
            .integer => |right_integer| switch (op) {
                .add => .{ .integer = left_integer +% right_integer },
                .sub => .{ .integer = left_integer -% right_integer },
                .mul => .{ .integer = left_integer *% right_integer },
                .idiv => if (right_integer == 0) null else .{ .integer = floorDiv(left_integer, right_integer) },
                .mod => if (right_integer == 0) null else .{ .integer = floorMod(left_integer, right_integer) },
                .div => .{ .number = @as(f64, @floatFromInt(left_integer)) / @as(f64, @floatFromInt(right_integer)) },
                else => null,
            },
            .number => |right_number| switch (op) {
                .add => .{ .number = @as(f64, @floatFromInt(left_integer)) + right_number },
                .sub => .{ .number = @as(f64, @floatFromInt(left_integer)) - right_number },
                .mul => .{ .number = @as(f64, @floatFromInt(left_integer)) * right_number },
                .div => .{ .number = @as(f64, @floatFromInt(left_integer)) / right_number },
                .idiv => .{ .number = @floor(@as(f64, @floatFromInt(left_integer)) / right_number) },
                .mod => .{ .number = floorModNumber(@as(f64, @floatFromInt(left_integer)), right_number) },
                else => null,
            },
            else => null,
        },
        .number => |left_number| switch (rhs) {
            .integer => |right_integer| switch (op) {
                .add => .{ .number = left_number + @as(f64, @floatFromInt(right_integer)) },
                .sub => .{ .number = left_number - @as(f64, @floatFromInt(right_integer)) },
                .mul => .{ .number = left_number * @as(f64, @floatFromInt(right_integer)) },
                .div => .{ .number = left_number / @as(f64, @floatFromInt(right_integer)) },
                .idiv => .{ .number = @floor(left_number / @as(f64, @floatFromInt(right_integer))) },
                .mod => .{ .number = floorModNumber(left_number, @as(f64, @floatFromInt(right_integer))) },
                else => null,
            },
            .number => |right_number| switch (op) {
                .add => .{ .number = left_number + right_number },
                .sub => .{ .number = left_number - right_number },
                .mul => .{ .number = left_number * right_number },
                .div => .{ .number = left_number / right_number },
                .idiv => .{ .number = @floor(left_number / right_number) },
                .mod => .{ .number = floorModNumber(left_number, right_number) },
                else => null,
            },
            else => null,
        },
        else => null,
    };
}

inline fn rawIntegerBitwiseOpFast(lhs: Value, rhs: Value, comptime op: BinaryOp) ?Value {
    if (lhs != .integer or rhs != .integer) return null;
    return .{ .integer = rawBitwise(lhs.integer, rhs.integer, op) };
}

fn equalityHasMetamethod(lhs: Value, rhs: Value) bool {
    return switch (lhs) {
        .table => |table| rhs == .table and !(noMetaEvent(table, .__eq) and noMetaEvent(rhs.table, .__eq)),
        .userdata => rhs == .userdata,
        else => false,
    };
}

fn rawCompareBranchResult(lhs: Value, rhs: Value, op: bytecode.CompareBranchOp) ?bool {
    return switch (op) {
        .eq => if (valuesEqual(lhs, rhs)) true else if (equalityHasMetamethod(lhs, rhs)) null else false,
        .lt => rawCompare(lhs, rhs, .lt),
        .le => rawCompare(lhs, rhs, .le),
    };
}

fn floorModNumber(left: f64, right: f64) f64 {
    var result = @rem(left, right);
    if (result != 0 and ((result < 0) != (right < 0))) result += right;
    return result;
}

fn rawUnaryOp(value: Value, op: UnaryMetamethodOp) ?Value {
    return switch (op) {
        .unm => switch (value) {
            .integer => |integer| .{ .integer = -%integer },
            .number => |number| .{ .number = -number },
            .string => if (toInteger(value)) |integer| .{ .integer = -%integer } else if (toNumberMaybe(value)) |number| .{ .number = -number } else null,
            else => null,
        },
        .bnot => if (toBitwiseInteger(value)) |integer| .{ .integer = ~integer } else null,
    };
}

fn toBitwiseInteger(value: Value) ?i64 {
    return switch (value) {
        .integer => |integer| integer,
        .number => |number| floatToInteger(number),
        else => null,
    };
}

fn isNumber(value: Value) bool {
    return value == .integer or value == .number;
}

fn rawBitwise(left: i64, right: i64, op: BinaryOp) i64 {
    return switch (op) {
        .band => left & right,
        .bor => left | right,
        .bxor => left ^ right,
        .shl => shiftInteger(left, right),
        .shr => if (right == std.math.minInt(i64)) 0 else shiftInteger(left, -right),
        else => unreachable,
    };
}

fn shiftInteger(value: i64, amount: i64) i64 {
    if (amount == 0) return value;
    if (amount >= 64 or amount <= -64) return 0;
    return if (amount > 0)
        value << @intCast(amount)
    else
        @as(i64, @bitCast(@as(u64, @bitCast(value)) >> @intCast(-amount)));
}

fn rawCompare(lhs: Value, rhs: Value, op: CompareOp) ?bool {
    return switch (lhs) {
        .integer => |left| switch (rhs) {
            .integer => |right| switch (op) {
                .lt => left < right,
                .le => left <= right,
            },
            .number => |right| compareIntegerNumber(left, right, op),
            else => null,
        },
        .number => |left| switch (rhs) {
            .integer => |right| compareNumberInteger(left, right, op),
            .number => |right| switch (op) {
                .lt => left < right,
                .le => left <= right,
            },
            else => null,
        },
        .string => |left| switch (rhs) {
            .string => |right| switch (op) {
                .lt => std.mem.lessThan(u8, left, right),
                .le => !std.mem.lessThan(u8, right, left),
            },
            else => null,
        },
        else => null,
    };
}

fn compareIntegerNumber(integer: i64, number: f64, op: CompareOp) bool {
    if (std.math.isNan(number)) return false;
    const min = @as(f64, @floatFromInt(std.math.minInt(i64)));
    const max_exclusive = -min;
    return switch (op) {
        .lt => {
            if (number <= min) return false;
            if (number >= max_exclusive) return true;
            return integer < @as(i64, @intFromFloat(@ceil(number)));
        },
        .le => {
            if (number < min) return false;
            if (number >= max_exclusive) return true;
            return integer <= @as(i64, @intFromFloat(@floor(number)));
        },
    };
}

fn compareNumberInteger(number: f64, integer: i64, op: CompareOp) bool {
    if (std.math.isNan(number)) return false;
    return switch (op) {
        .lt => !compareIntegerNumber(integer, number, .le),
        .le => !compareIntegerNumber(integer, number, .lt),
    };
}

fn binaryMetamethod(op: BinaryOp) []const u8 {
    return switch (op) {
        .add => "__add",
        .sub => "__sub",
        .mul => "__mul",
        .div => "__div",
        .idiv => "__idiv",
        .mod => "__mod",
        .pow => "__pow",
        .band => "__band",
        .bor => "__bor",
        .bxor => "__bxor",
        .shl => "__shl",
        .shr => "__shr",
        .concat => "__concat",
    };
}

fn unaryMetamethod(op: UnaryMetamethodOp) []const u8 {
    return switch (op) {
        .unm => "__unm",
        .bnot => "__bnot",
    };
}

pub fn valuesEqual(lhs: Value, rhs: Value) bool {
    return value_mod.valuesEqual(lhs, rhs);
}

fn hashValue(value: Value) u64 {
    return switch (value) {
        .nil => hashTag(0),
        .boolean => |payload| hashBool(1, payload),
        .integer => |payload| hashInteger(payload),
        .number => |payload| if (floatToInteger(payload)) |integer| hashInteger(integer) else hashFloat(payload),
        .string => |payload| hashBytes(4, payload),
        .table => |payload| hashPointer(5, payload),
        .userdata => |payload| hashPointer(6, payload),
        .closure => |payload| hashPointer(7, payload),
        .thread => |payload| hashPointer(9, payload),
        .coroutine_wrapper => |payload| hashPointer(10, payload),
        .gmatch_iterator => |payload| hashPointer(11, payload),
        .native_print => hashTag(12),
        .native_tostring => hashTag(13),
        .native_getmetatable => hashTag(14),
        .native_setmetatable => hashTag(15),
        .native_rawequal => hashTag(16),
        .native_rawget => hashTag(17),
        .native_rawset => hashTag(18),
        .native_rawlen => hashTag(19),
        .native_next => hashTag(20),
        .native_pairs => hashTag(21),
        .native_ipairs => hashTag(22),
        .native_ipairs_iter => hashTag(23),
        .native_table_create => hashTag(24),
        .native_select => hashTag(25),
        .native_assert => hashTag(26),
        .native_error => hashTag(27),
        .native_pcall => hashTag(28),
        .native_xpcall => hashTag(29),
        .native_collectgarbage => hashTag(30),
        .native_debug_traceback => hashTag(31),
        .native_coroutine_create => hashTag(32),
        .native_coroutine_resume => hashTag(33),
        .native_coroutine_yield => hashTag(34),
        .native_coroutine_status => hashTag(35),
        .native_coroutine_running => hashTag(36),
        .native_coroutine_isyieldable => hashTag(37),
        .native_coroutine_close => hashTag(38),
        .native_coroutine_wrap => hashTag(39),
        .native => |payload| hashEnum(40, payload),
        .api_callback => |id| std.hash.Wyhash.hash(hashTag(41), std.mem.asBytes(&id)),
    };
}

fn hashTag(tag: u8) u64 {
    return std.hash.Wyhash.hash(0, &.{tag});
}

fn hashBytes(tag: u8, bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(hashTag(tag), bytes);
}

fn hashBool(tag: u8, value: bool) u64 {
    const byte: u8 = if (value) 1 else 0;
    return std.hash.Wyhash.hash(hashTag(tag), &.{byte});
}

fn hashInteger(value: i64) u64 {
    const bits: u64 = @bitCast(value);
    return std.hash.Wyhash.hash(hashTag(2), std.mem.asBytes(&bits));
}

fn hashFloat(value: f64) u64 {
    const bits: u64 = @bitCast(value);
    return std.hash.Wyhash.hash(hashTag(3), std.mem.asBytes(&bits));
}

fn hashPointer(tag: u8, pointer: anytype) u64 {
    const address = @intFromPtr(pointer);
    return std.hash.Wyhash.hash(hashTag(tag), std.mem.asBytes(&address));
}

fn hashEnum(tag: u8, value: anytype) u64 {
    const integer = @intFromEnum(value);
    return std.hash.Wyhash.hash(hashTag(tag), std.mem.asBytes(&integer));
}

fn isNativeCallable(value: Value) bool {
    return switch (value) {
        .native_print,
        .native_tostring,
        .native_getmetatable,
        .native_setmetatable,
        .native_rawequal,
        .native_rawget,
        .native_rawset,
        .native_rawlen,
        .native_next,
        .native_pairs,
        .native_ipairs,
        .native_ipairs_iter,
        .native_table_create,
        .native_select,
        .native_assert,
        .native_error,
        .native_pcall,
        .native_xpcall,
        .native_collectgarbage,
        .native_debug_traceback,
        .native_coroutine_create,
        .native_coroutine_resume,
        .native_coroutine_yield,
        .native_coroutine_status,
        .native_coroutine_running,
        .native_coroutine_isyieldable,
        .native_coroutine_close,
        .native_coroutine_wrap,
        .native,
        .api_callback,
        => true,
        else => false,
    };
}

fn isYieldBlockingNative(value: Value) bool {
    return switch (value) {
        .native_pcall, .native_xpcall => false,
        .native => |native| native != .dofile,
        else => isNativeCallable(value),
    };
}

fn functionLike(value: Value) bool {
    return switch (value) {
        .closure, .coroutine_wrapper, .gmatch_iterator => true,
        else => isNativeCallable(value),
    };
}

fn threadStatusName(status: ThreadStatus) []const u8 {
    return switch (status) {
        .suspended => "suspended",
        .running => "running",
        .normal => "normal",
        .dead => "dead",
    };
}

fn resumeChainDepth(thread: ?*Thread) usize {
    var depth: usize = 0;
    var current = thread;
    while (current) |active| : (current = active.resume_parent) depth += 1;
    return depth;
}

fn lessThan(lhs: Value, rhs: Value) !bool {
    return switch (lhs) {
        .integer, .number => (try toNumber(lhs)) < (try toNumber(rhs)),
        .string => |left| switch (rhs) {
            .string => |right| std.mem.lessThan(u8, left, right),
            else => error.RuntimeError,
        },
        else => error.RuntimeError,
    };
}

fn lessEqual(lhs: Value, rhs: Value) !bool {
    return valuesEqual(lhs, rhs) or try lessThan(lhs, rhs);
}

pub fn truthy(value: Value) bool {
    return value_mod.truthy(value);
}

pub fn toInteger(value: Value) ?i64 {
    return value_mod.toInteger(value);
}

pub fn toNumber(value: Value) !f64 {
    return value_mod.toNumber(value);
}

fn toNumberMaybe(value: Value) ?f64 {
    return value_mod.toNumberMaybe(value);
}

fn luaStringLike(value: Value) bool {
    return value_mod.luaStringLike(value);
}

fn indexErrorMessage(value: Value) []const u8 {
    return value_mod.indexErrorMessage(value);
}

fn callErrorMessage(value: Value) []const u8 {
    return value_mod.callErrorMessage(value);
}

fn nativeHookName(value: Value) ?[]const u8 {
    return value_mod.nativeHookName(value);
}

fn shortNativeName(name: []const u8) []const u8 {
    return value_mod.shortNativeName(name);
}

const DebugStackSlot = struct {
    frame_index: usize,
    register: usize,
};

fn debugStackRegister(thread: *Thread, stack_index: usize) ?DebugStackSlot {
    var frame_index = thread.frames.items.len;
    while (frame_index > 0) {
        frame_index -= 1;
        const frame = thread.frames.items[frame_index];
        const register_count: usize = @intCast(frame.proto.max_registers);
        if (stack_index >= frame.base and stack_index < frame.base + register_count) {
            return .{ .frame_index = frame_index, .register = stack_index - frame.base };
        }
    }
    return null;
}

fn debugValueTypeName(value: Value) []const u8 {
    return value_mod.debugValueTypeName(value);
}

pub fn appendLuaString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    return value_mod.appendLuaString(allocator, out, value);
}

fn floorDiv(left: i64, right: i64) i64 {
    if (left == std.math.minInt(i64) and right == -1) return left;
    return @divFloor(left, right);
}

fn floorMod(left: i64, right: i64) i64 {
    if (left == std.math.minInt(i64) and right == -1) return 0;
    return @mod(left, right);
}

fn jumpTarget(pc: usize, offset: bytecode.JumpOffset) usize {
    return if (offset >= 0) pc + @as(usize, @intCast(offset)) else pc - @as(usize, @intCast(-offset));
}

fn instructionPreservesLastResult(instruction: bytecode.Instruction) bool {
    return switch (instruction) {
        .call, .tail_call, .ret, .vararg => true,
        else => false,
    };
}

fn plainFastLoopCanStart(instruction: bytecode.Instruction) bool {
    return switch (instruction) {
        .load_nil,
        .load_bool,
        .load_const,
        .move,
        .get_upvalue,
        .set_upvalue,
        .add,
        .sub,
        .mul,
        .div,
        .idiv,
        .mod,
        .band,
        .bor,
        .bxor,
        .shl,
        .shr,
        .eq,
        .lt,
        .le,
        .not,
        .unm,
        .bnot,
        .len,
        .get_table,
        .get_field,
        .set_table,
        .set_array,
        .set_field,
        .compare_branch,
        .jmp,
        .test_op,
        .test_set,
        .for_loop,
        .call,
        .ret,
        .close,
        => true,
        else => false,
    };
}

fn forLoopContinuesInteger(current: i64, limit: i64, step: i64) bool {
    return if (step > 0) current <= limit else current >= limit;
}

fn integerForLimit(limit: f64, step: i64) ?i64 {
    if (std.math.isNan(limit)) return null;
    const min_integer: f64 = @floatFromInt(std.math.minInt(i64));
    const max_integer: f64 = @floatFromInt(std.math.maxInt(i64));
    if (step > 0) {
        if (limit < min_integer) return null;
        if (limit >= max_integer) return std.math.maxInt(i64);
        return @intFromFloat(std.math.floor(limit));
    }
    if (limit > max_integer) return null;
    if (limit <= min_integer) return std.math.minInt(i64);
    return @intFromFloat(std.math.ceil(limit));
}

fn forLoopContinuesNumber(current: f64, limit: f64, step: f64) bool {
    return if (step > 0) current <= limit else current >= limit;
}

pub fn localActiveAt(local: proto_mod.LocalDebug, pc: usize) bool {
    return value_mod.localActiveAt(local, pc);
}

fn isRuntimeError(err: anyerror) bool {
    return switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => true,
        else => false,
    };
}

fn lineForFrame(frame: CallFrame) ?usize {
    if (frame.proto.line_info.items.len == 0) return null;
    const pc = if (frame.pc == 0) 0 else frame.pc - 1;
    if (pc >= frame.proto.line_info.items.len) return null;
    const line = frame.proto.line_info.items[pc].line;
    return if (line == 0) null else line;
}

fn setProtoSourceName(proto: *proto_mod.Proto, name: []const u8) !void {
    proto.source_name = try proto.arena.allocator().dupe(u8, name);
    for (proto.children.items) |child| try setProtoSourceName(child, name);
}

fn copyStackValues(thread: *Thread, dest: usize, source: usize, count: usize) void {
    if (count == 0 or dest == source) return;
    if (dest > source and dest < source + count) {
        var index = count;
        while (index > 0) {
            index -= 1;
            thread.stack.items[dest + index] = thread.stack.items[source + index];
        }
    } else {
        for (0..count) |index| thread.stack.items[dest + index] = thread.stack.items[source + index];
    }
}

fn constantString(proto: *const proto_mod.Proto, index: bytecode.ConstantIndex) []const u8 {
    return proto.constants.items[index].string;
}

fn parseIntegerLiteral(lexeme: []const u8) !Value {
    return value_mod.parseIntegerLiteral(lexeme);
}

pub fn parseIntegerStrict(text: []const u8) ?i64 {
    return value_mod.parseIntegerStrict(text);
}

pub fn parseLuaNumber(text: []const u8) !f64 {
    return value_mod.parseLuaNumber(text);
}

fn parseHexNumber(text: []const u8) !f64 {
    var index: usize = 2;
    var value: f64 = 0;
    var digits: usize = 0;
    while (index < text.len and std.ascii.isHex(text[index])) : (index += 1) {
        value = value * 16 + @as(f64, @floatFromInt(hexValue(text[index])));
        digits += 1;
    }
    if (index < text.len and text[index] == '.') {
        index += 1;
        var place: f64 = 1.0 / 16.0;
        while (index < text.len and std.ascii.isHex(text[index])) : (index += 1) {
            value += @as(f64, @floatFromInt(hexValue(text[index]))) * place;
            place /= 16.0;
            digits += 1;
        }
    }
    if (digits == 0) return error.RuntimeError;

    var exponent: i32 = 0;
    if (index < text.len and (text[index] == 'p' or text[index] == 'P')) {
        index += 1;
        var sign: i32 = 1;
        if (index < text.len and (text[index] == '+' or text[index] == '-')) {
            sign = if (text[index] == '-') -1 else 1;
            index += 1;
        }
        const exponent_start = index;
        while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {
            exponent = exponent * 10 + @as(i32, @intCast(text[index] - '0'));
        }
        if (index == exponent_start) return error.RuntimeError;
        exponent *= sign;
    }
    if (index != text.len) return error.RuntimeError;
    return value * std.math.pow(f64, 2.0, @floatFromInt(exponent));
}

pub fn floatToInteger(number: f64) ?i64 {
    return value_mod.floatToInteger(number);
}

fn isHex(text: []const u8) bool {
    return value_mod.isHex(text);
}

pub fn trimAscii(text: []const u8) []const u8 {
    return value_mod.trimAscii(text);
}

fn arrayIndex(value: Value) ?usize {
    return value_mod.arrayIndex(value);
}

fn fastTableArrayGet(table_value: Value, key_value: Value) ?Value {
    if (table_value != .table) return null;
    const index = arrayIndex(key_value) orelse return null;
    const table = table_value.table;
    if (index > table.array.items.len) return null;
    const value = table.array.items[index - 1];
    if (value != .nil or noIndexMetamethod(table)) return value;
    return null;
}

inline fn noMetaEvent(table: *const Table, comptime event: types.MetaEvent) bool {
    const metatable = table.metatable orelse return true;
    return metatable.metaEventAbsent(event);
}

inline fn noIndexMetamethod(table: *const Table) bool {
    return noMetaEvent(table, .__index);
}

inline fn noNewindexMetamethod(table: *const Table) bool {
    return noMetaEvent(table, .__newindex);
}

fn assertProtoPrepared(proto: *const proto_mod.Proto) void {
    std.debug.assert(proto.runtime_prepared or proto.constants.items.len == 0);
}

inline fn hasPendingContinuations(thread: *const Thread) bool {
    return (thread.pairs_continuations.items.len |
        thread.call_one_continuations.items.len |
        thread.protected_continuations.items.len |
        thread.tail_call_continuations.items.len |
        thread.generic_for_continuations.items.len) != 0;
}

fn fastTableRawGet(table_value: Value, key_value: Value) ?Value {
    if (fastTableArrayGet(table_value, key_value)) |value| return value;
    if (table_value != .table or key_value != .string) return null;
    const table = table_value.table;
    const value = table.get(key_value);
    if (value != .nil) return value;
    const metatable = table.metatable orelse return value;
    if (metatable.metaEventAbsent(.__index)) return value;
    const handler = metatable.metaEvent(.__index);
    if (handler == .nil) return value;
    if (handler != .table) return null;
    const inherited = handler.table.get(key_value);
    if (inherited != .nil or noIndexMetamethod(handler.table)) return inherited;
    return null;
}

fn fastLengthNoMetamethod(value: Value) ?Value {
    return switch (value) {
        .string => |string| .{ .integer = @intCast(string.len) },
        .table => |table| if (noMetaEvent(table, .__len)) .{ .integer = table.len() } else null,
        else => null,
    };
}

pub fn runtimeArgValue(state: *State, thread: *Thread, op: bytecode.Call, index: u32) Value {
    return value_mod.runtimeArgValue(state, thread, op, index);
}

pub fn argValue(state: *State, thread: *Thread, op: bytecode.Call, index: u32) Value {
    return value_mod.argValue(state, thread, op, index);
}

/// Like `appendValue`, but a nil error object becomes `<no error object>`.
pub fn appendErrorValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    if (value == .nil) return out.appendSlice(allocator, "<no error object>");
    return appendValue(allocator, out, value);
}

/// Formats without metamethods; file handles format like their `__tostring`.
pub fn appendValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    if (stdlib.io.fileOf(value)) |file| {
        if (file.closed) return out.appendSlice(allocator, "file (closed)");
        return appendFmt(allocator, out, "file (0x{x})", .{@intFromPtr(value.userdata)});
    }
    return value_mod.appendValue(allocator, out, value);
}

pub fn isFileValue(value: Value) bool {
    return stdlib.io.fileOf(value) != null;
}

pub fn isClosedFileValue(value: Value) bool {
    const file = stdlib.io.fileOf(value) orelse return false;
    return file.closed;
}

fn appendNamedValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: Value) !void {
    return value_mod.appendNamedValue(allocator, out, name, value);
}

fn freeProtectedResult(allocator: std.mem.Allocator, result: ProtectedCallResult) void {
    return value_mod.freeProtectedResult(allocator, result);
}

fn freeCoroutineResumeResult(allocator: std.mem.Allocator, result: CoroutineResumeResult) void {
    switch (result) {
        .success => |values| allocator.free(values),
        .failure => {},
    }
}

pub fn appendNumber(allocator: std.mem.Allocator, out: *std.ArrayList(u8), number: f64) !void {
    return value_mod.appendNumber(allocator, out, number);
}

pub fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    return value_mod.appendFmt(allocator, out, fmt, args);
}

fn hexValue(byte: u8) u32 {
    return value_mod.hexValue(byte);
}

const max_lua_utf8_codepoint: u32 = 0x7fffffff;

fn appendUnicodeEscapeDigit(value: u32, digit: u32) u32 {
    if (value > max_lua_utf8_codepoint / 16) return max_lua_utf8_codepoint + 1;
    const next = value * 16 + digit;
    if (next > max_lua_utf8_codepoint) return max_lua_utf8_codepoint + 1;
    return next;
}

fn encodeLuaUtf8(code: u32, out: *[6]u8) ?usize {
    if (code <= 0x7f) {
        out[0] = @intCast(code);
        return 1;
    }
    if (code <= 0x7ff) {
        out[0] = 0xc0 | @as(u8, @intCast(code >> 6));
        out[1] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 2;
    }
    if (code <= 0xffff) {
        out[0] = 0xe0 | @as(u8, @intCast(code >> 12));
        out[1] = 0x80 | @as(u8, @intCast((code >> 6) & 0x3f));
        out[2] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 3;
    }
    if (code <= 0x1fffff) {
        out[0] = 0xf0 | @as(u8, @intCast(code >> 18));
        out[1] = 0x80 | @as(u8, @intCast((code >> 12) & 0x3f));
        out[2] = 0x80 | @as(u8, @intCast((code >> 6) & 0x3f));
        out[3] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 4;
    }
    if (code <= 0x3ffffff) {
        out[0] = 0xf8 | @as(u8, @intCast(code >> 24));
        out[1] = 0x80 | @as(u8, @intCast((code >> 18) & 0x3f));
        out[2] = 0x80 | @as(u8, @intCast((code >> 12) & 0x3f));
        out[3] = 0x80 | @as(u8, @intCast((code >> 6) & 0x3f));
        out[4] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 5;
    }
    if (code <= max_lua_utf8_codepoint) {
        out[0] = 0xfc | @as(u8, @intCast(code >> 30));
        out[1] = 0x80 | @as(u8, @intCast((code >> 24) & 0x3f));
        out[2] = 0x80 | @as(u8, @intCast((code >> 18) & 0x3f));
        out[3] = 0x80 | @as(u8, @intCast((code >> 12) & 0x3f));
        out[4] = 0x80 | @as(u8, @intCast((code >> 6) & 0x3f));
        out[5] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 6;
    }
    return null;
}
