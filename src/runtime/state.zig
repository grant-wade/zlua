const std = @import("std");
const compile = @import("../compile.zig");
const errors = @import("../errors.zig");
const stdlib = @import("../stdlib.zig");
const stdlib_static_strings = @import("../stdlib/static_strings.zig");
const budget_mod = @import("budget.zig");
const call_mod = @import("call.zig");
const coroutine_mod = @import("coroutine.zig");
const debug_mod = @import("debug.zig");
const failure_mod = @import("failure.zig");
const gc_mod = @import("gc.zig");
const host = @import("host.zig");
const index_mod = @import("index.zig");
const load_mod = @import("load.zig");
const metatable_mod = @import("metatable.zig");
const ObjectPool = @import("object_pool.zig").ObjectPool;
const rollback_mod = @import("rollback.zig");
const strings_mod = @import("strings.zig");
const timezone = @import("timezone.zig");
const types = @import("types.zig");
const upvalue_mod = @import("upvalue.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const bytecode = compile.bytecode;
const proto_mod = compile.proto;
pub const RuntimeError = types.RuntimeError;

const default_max_stack_values: usize = 1_000_000;
const default_max_call_frames: usize = 1_000_000;
pub const lua_max_c_calls: usize = 200;
pub const stack_error_frames: usize = 32;
pub const stack_error_values: usize = 200;
pub const max_metamethod_depth: usize = 15;

pub const Value = types.Value;
pub const NativeFn = types.NativeFn;
pub const UserdataFinalizer = types.UserdataFinalizer;
pub const UserdataDeinit = types.UserdataDeinit;
pub const ProtectedCallResult = types.ProtectedCallResult;
pub const ApiCallbackDispatchFn = types.ApiCallbackDispatchFn;
pub const ApiCallbackContext = types.ApiCallbackContext;
pub const RuntimeErrorPayload = types.RuntimeErrorPayload;

const valuesEqual = value_mod.valuesEqual;
const toInteger = value_mod.toInteger;
const toNumberMaybe = value_mod.toNumberMaybe;
const floatToInteger = value_mod.floatToInteger;
const argValue = value_mod.argValue;
const appendFmt = value_mod.appendFmt;

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

pub const Closure = types.Closure;
pub const Upvalue = types.Upvalue;
pub const Table = types.Table;
pub const Userdata = types.Userdata;
pub const Thread = types.Thread;
pub const GcMode = types.GcMode;
pub const GcParam = types.GcParam;

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
    /// Holds the tables, upvalues, closures and strings, over `allocator`.
    object_pool: *ObjectPool,
    global_table: ?*Table = null,
    strings: strings_mod.Strings = .{},
    string_allocations: std.ArrayList(*types.String) = .empty,
    table_allocations: std.ArrayList(*Table) = .empty,
    table_finalizer_head: ?*Table = null,
    table_finalizer_serial: u64 = 0,
    table_pending_finalizer_head: ?*Table = null,
    /// Userdata awaiting Lua `__gc`, ordered together with `table_pending_finalizer_head`.
    userdata_lua_pending_head: ?*Userdata = null,
    userdata_pending_finalizer_head: ?*Userdata = null,
    userdata_allocations: std.ArrayList(*Userdata) = .empty,
    closure_allocations: std.ArrayList(*Closure) = .empty,
    upvalue_allocations: std.ArrayList(*Upvalue) = .empty,
    thread_allocations: std.ArrayList(*Thread) = .empty,
    chunk_allocations: std.ArrayList(*types.Chunk) = .empty,
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

    pub fn registerAllocation(self: *State, comptime field: []const u8, item: anytype) !void {
        if (self.rollback) |journal| try journal.prepareAllocation(self);
        try self.gc.prepareRegistration(field);
        try @field(self, field).append(self.allocator, item);
        self.gc.registeredAllocation(field, item);
    }

    pub fn init(allocator: std.mem.Allocator) !State {
        return initWithOptions(allocator, .{});
    }

    pub inline fn objects(self: *const State) std.mem.Allocator {
        return self.object_pool.allocator();
    }

    pub inline fn allocatorFor(self: *const State, comptime T: type) std.mem.Allocator {
        return if (T == Table or T == types.Upvalue or T == Closure or T == types.String) self.objects() else self.allocator;
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
            .object_pool = try ObjectPool.create(allocator),
            .options = options,
            .warnings_on = options.warnings,
        };
        errdefer state.deinit();

        const hints = stdlib.initHints(options.stdlib);
        state.strings.set = try strings_mod.InternSet.initStatic(allocator, hints.strings);
        try state.string_allocations.ensureTotalCapacity(allocator, hints.strings);
        try state.table_allocations.ensureTotalCapacity(allocator, hints.tables);
        observe(observer_context, .state, &state);

        try stdlib.installGlobalTableWithHint(&state, hints.globals);
        observe(observer_context, .globals, &state);

        try stdlib.openLibraries(&state, options.stdlib);
        observe(observer_context, .libraries, &state);

        _ = state.gc.refreshAllocationTotal();
        state.gc.normalizeBaseline();
        observe(observer_context, .gc_baseline, &state);
        return state;
    }

    pub fn stackValueLimit(self: *const State) usize {
        return if (self.options.max_stack_values) |limit| @min(limit, default_max_stack_values) else default_max_stack_values;
    }

    pub fn stressPending(self: *const State) bool {
        return (self.gc.stress_collect or self.gc.stress_step) and self.gc.known_total != self.gc.stress_mark;
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
        for (file_metatable.entries()) |entry| {
            if (entry.value != .nil) try state.setTableRaw(metatable, entry.key, entry.value);
        }
        const methods = try state.newTableWithHints(0, 12);
        try state.setTableRaw(metatable, .{ .string = stdlib_static_strings.get("__index") }, methods);
        try setFileMethods(state, methods.table);
        try state.setTableRaw(methods.table, .{ .string = try state.strings.intern("stat") }, .{ .native = .fs_file_stat });
        try state.setTableRaw(methods.table, .{ .string = try state.strings.intern("tell") }, .{ .native = .fs_file_tell });
        try state.setTableRaw(methods.table, .{ .string = try state.strings.intern("truncate") }, .{ .native = .fs_file_truncate });
        try state.setTableRaw(methods.table, .{ .string = stdlib_static_strings.get("path") }, .{ .native = .fs_file_path });
        try state.setTableRaw(methods.table, .{ .string = try state.strings.intern("sync") }, .{ .native = .io_file_flush });
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
            if (run_finalizers) self.gc.runCloseFinalizers();
            stdlib.io.closeOpenFiles(self);
        }
        self.snapshot_busy = true;
        if (self.local_zone) |zone| {
            zone.deinit();
            self.allocator.destroy(zone);
        }
        if (self.budget.interrupt) |control| self.allocator.destroy(control);
        self.stdout.deinit(self.allocator);
        self.stderr.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.gc.work.deinit(self.allocator);
        self.gc.remembered.deinit(self.allocator);
        self.gc.weak.deinit(self.allocator);
        self.gc.tables.deinit(self.allocator);
        self.gc.finalizers.deinit(self.allocator);
        for (self.thread_allocations.items) |thread| self.gc.destroyThread(thread);
        for (self.closure_allocations.items) |closure| self.gc.destroyClosure(closure);
        for (self.upvalue_allocations.items) |upvalue| self.objects().destroy(upvalue);
        for (self.userdata_allocations.items) |userdata| self.gc.destroyUserdata(userdata);
        for (self.table_allocations.items) |table| {
            if (self.discarding) {
                table.deinit(self.allocator);
                self.objects().destroy(table);
            } else self.gc.destroyTable(table);
        }
        for (self.chunk_allocations.items) |chunk| chunk.destroy(self.allocator);
        for (self.source_allocations.items) |source| self.allocator.free(source);
        for (self.string_allocations.items) |string| strings_mod.destroy(self.objects(), string);
        self.api_roots.deinit(self.allocator);
        self.source_allocations.deinit(self.allocator);
        self.chunk_allocations.deinit(self.allocator);
        self.thread_allocations.deinit(self.allocator);
        self.upvalue_allocations.deinit(self.allocator);
        self.closure_allocations.deinit(self.allocator);
        self.userdata_allocations.deinit(self.allocator);
        self.table_allocations.deinit(self.allocator);
        self.string_allocations.deinit(self.allocator);
        self.object_pool.destroy();
        self.* = undefined;
    }

    pub fn setTableRaw(self: *State, table: *Table, key: Value, value: Value) !void {
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        defer self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
        try table.set(self.allocator, key, value);
        self.gc.writeTableBarrier(table, key, value);
    }

    pub fn declareGlobal(self: *State, thread: *Thread, name: []const u8, table_register: bytecode.Register, value_register: bytecode.Register) !void {
        const table_value = vm_mod.get(self, thread, table_register);
        if (table_value != .table) return failure_mod.failRuntimeDetail(self, thread, "attempt to index a nil value");
        const key = Value{ .string = try self.strings.intern(name) };
        if (table_value.table.get(key) != .nil) {
            const message = try std.fmt.allocPrint(self.allocator, "global '{s}' already defined", .{name});
            defer self.allocator.free(message);
            return self.failString(try self.strings.intern(message));
        }
        try index_mod.setTable(self, table_value, key, vm_mod.get(self, thread, value_register));
    }

    pub fn setGlobal(self: *State, name: []const u8, value: Value) !void {
        return self.setGlobalString(try self.strings.intern(name), value);
    }

    pub fn setGlobalString(self: *State, key: *const types.String, value: Value) !void {
        const table = self.global_table orelse return error.RuntimeError;
        try self.setTableRaw(table, .{ .string = key }, value);
        self.gc.markValue(value);
    }

    pub fn getGlobalValue(self: *State, name: []const u8) Value {
        const table = self.global_table orelse return .nil;
        return table.getBytes(name);
    }

    pub fn getGlobal(self: *State, name: []const u8) Value {
        return self.getGlobalValue(name);
    }

    pub fn putGlobal(self: *State, name: []const u8, value: Value) !void {
        try self.setGlobal(name, value);
    }

    pub fn rootValue(self: *State, value: Value) !usize {
        for (self.api_roots.items, 0..) |root, index| {
            if (root == .nil) {
                self.api_roots.items[index] = value;
                self.gc.markValue(value);
                return index;
            }
        }
        try self.api_roots.append(self.allocator, value);
        self.gc.markValue(value);
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
            error.HostCallbackYield => return coroutine_mod.suspendCoroutine(self, thread, op, context.returns.items()),
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => return err,
            error.LuaError => return self.failValue(context.error_value orelse .{ .string = try self.strings.intern("host callback raised an error") }),
            error.OutOfMemory, error.LuaExit, error.Interrupted => return err,
            else => return self.fail(@errorName(err)),
        };

        try self.returnValues(thread, op.base, op.return_count, context.returns.items());
    }

    pub fn newTableWithHints(self: *State, array_hint: u32, hash_hint: u32) !Value {
        const table = try self.objects().create(Table);
        errdefer self.objects().destroy(table);
        table.* = try Table.init(self.allocator, array_hint, hash_hint);
        errdefer table.deinit(self.allocator);
        try self.registerAllocation("table_allocations", table);
        self.gc.noteAllocation(gc_mod.tableGcBytes(table));
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
        self.gc.noteAllocation(gc_mod.userdataBytes(userdata));
        return .{ .userdata = userdata };
    }

    pub fn newClosure(self: *State, thread: *Thread, proto: *const proto_mod.Proto) !Value {
        const parent = thread.frames.items[thread.frames.items.len - 1];
        vm_mod.assertProtoPrepared(proto);
        const closure = try Closure.create(self.objects(), proto.upvalues.items.len, .{ .proto = proto, .chunk = parent.closure.chunk, .stripped_debug = parent.closure.stripped_debug });
        errdefer Closure.destroy(self.objects(), closure);
        const upvalues = closure.upvalues();
        for (proto.upvalues.items, upvalues) |desc, *upvalue| {
            upvalue.* = if (desc.in_stack)
                try upvalue_mod.captureUpvalue(self, thread, parent.base + desc.index)
            else
                parent.closure.upvalues()[desc.index];
        }
        try self.registerAllocation("closure_allocations", closure);
        self.gc.noteAllocation(Closure.allocationBytes(upvalues.len));
        return .{ .closure = closure };
    }

    pub fn returnValues(self: *State, thread: *Thread, base: u32, return_count: u16, values: []const Value) !void {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        const actual_count = try call_mod.resolveReturnCount(self, return_count, values.len);
        const absolute_base = frame.base + base;
        const stored_count = @max(actual_count, values.len);
        try thread.ensureStack(self.allocator, absolute_base + stored_count, call_mod.callStackValueLimit(self, thread));
        for (0..stored_count) |index| {
            thread.stack.items[absolute_base + index] = if (index < values.len) values[index] else .nil;
        }
        thread.last_result_base = absolute_base;
        thread.last_result_count = actual_count;
        thread.last_transfer_base = absolute_base;
        thread.last_transfer_count = values.len;
    }

    pub fn expectTable(self: *State, value: Value) !*Table {
        return switch (value) {
            .table => |table| table,
            else => self.fail("table expected"),
        };
    }

    pub fn expectString(self: *State, value: Value) ![]const u8 {
        return switch (value) {
            .string => |string| string.bytes(),
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

    pub fn fail(self: *State, message: []const u8) RuntimeError {
        return self.failString(try self.strings.intern(message));
    }

    pub fn failString(self: *State, message: *const types.String) RuntimeError {
        self.last_error = .{ .lua_value = .{ .string = message } };
        self.error_handled = false;
        return error.RuntimeError;
    }

    /// Like `luaL_argerror`; `index` is 1-based and `function_name` is the fallback name.
    fn failArgument(self: *State, function_name: []const u8, index: u32, detail: errors.ArgumentErrorDetail) RuntimeError {
        const rendered = self.renderArgumentError(function_name, index, detail) catch return error.OutOfMemory;
        return self.failString(rendered);
    }

    pub fn failArgumentMessage(self: *State, function_name: []const u8, index: u32, message: []const u8) RuntimeError {
        return self.failArgument(function_name, index, .{ .message = message });
    }

    pub fn failArgumentType(self: *State, function_name: []const u8, index: u32, expected: []const u8, actual: Value) RuntimeError {
        return self.failArgument(function_name, index, .{ .expected = .{
            .expected = expected,
            .actual = metatable_mod.luaTypeNameForError(self, actual),
        } });
    }

    /// Like `luaL_error`: prefixes the calling Lua code's position.
    pub fn failLibrary(self: *State, message: []const u8) RuntimeError {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        self.appendLibraryWhere(&out) catch return self.fail(message);
        if (out.items.len == 0) return self.fail(message);
        out.appendSlice(self.allocator, message) catch return self.fail(message);
        return self.failString(self.strings.intern(out.items) catch return self.fail(message));
    }

    /// Prefixes a string error with `luaL_where(L, 1)`, as `coroutine.wrap` does.
    pub fn withLibraryWhere(self: *State, value: Value) !Value {
        if (value != .string) return value;
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        try self.appendLibraryWhere(&out);
        if (out.items.len == 0) return value;
        try out.appendSlice(self.allocator, value.string.bytes());
        return .{ .string = try self.strings.intern(out.items) };
    }

    pub fn failLibraryFmt(self: *State, comptime fmt: []const u8, args: anytype) RuntimeError {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator);
        appendFmt(self.allocator, &out, fmt, args) catch return error.OutOfMemory;
        return self.failLibrary(out.items);
    }

    pub fn activeNativeCall(thread: *Thread) ?types.NativeCall {
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
        const site = failure_mod.instructionErrorSite(self, thread) orelse return;
        try appendFmt(self.allocator, out, "{s}:{d}: ", .{ load_mod.runtimeSourceName(frame.closure.proto.source_name), site.line });
    }

    const CallName = struct { name: []const u8, namewhat: []const u8 };

    /// Also true for a metamethod the `ipairs` iterator called during a generic-for step.
    fn calledFromNative(thread: *Thread, call: types.NativeCall) bool {
        if (call.from_native) return true;
        const namewhat = call.namewhat orelse return false;
        if (!std.mem.eql(u8, namewhat, "metamethod")) return false;
        const frame = thread.frames.items[thread.frames.items.len - 1];
        if (frame.pc == 0 or frame.pc > frame.closure.proto.instructions.items.len) return false;
        return switch (frame.closure.proto.instructions.items[frame.pc - 1]) {
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
        if (call.base >= frame.closure.proto.max_registers) return null;
        const site = failure_mod.instructionErrorSite(self, thread) orelse return null;
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
        const package = globals.getLiteral("package");
        const loaded = if (package == .table) package.table.getLiteral("loaded") else Value.nil;
        const modules = if (loaded == .table) loaded.table else globals;
        for (modules.entries()) |entry| {
            if (entry.key != .string or entry.value != .table or entry.value.table == globals) continue;
            if (findFunctionField(entry.value.table, callee)) |key| {
                try appendFmt(self.allocator, out, "{s}.{s}", .{ entry.key.string.bytes(), key });
                return true;
            }
        }
        return false;
    }

    fn findFunctionField(table: *Table, callee: Value) ?[]const u8 {
        for (table.entries()) |entry| {
            if (entry.key == .string and valuesEqual(entry.value, callee)) return entry.key.string.bytes();
        }
        return null;
    }

    fn renderArgumentError(self: *State, function_name: []const u8, raw_index: u32, detail: errors.ArgumentErrorDetail) !*const types.String {
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
                    return self.strings.intern(out.items);
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
        return self.strings.intern(out.items);
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
            .string => |string| string.bytes(),
            .integer, .number => {
                var buffer: [value_mod.max_number_text_len]u8 = undefined;
                const string = try self.strings.intern(value_mod.formatNumber(&buffer, value));
                const frame = thread.frames.items[thread.frames.items.len - 1];
                thread.stack.items[frame.base + op.base + 1 + index] = .{ .string = string };
                return string.bytes();
            },
            else => self.failArgumentType(function_name, index + 1, "string", value),
        };
    }

    pub fn expectArgumentStringObject(self: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !*const types.String {
        _ = try self.expectArgumentString(thread, op, function_name, index);
        return argValue(self, thread, op, index).string;
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
