const std = @import("std");
const reflection = @import("../reflection.zig");
const runtime = @import("../runtime.zig");
const snapshot_runtime = @import("../runtime/snapshot.zig");
const stdlib = @import("../stdlib.zig");
const callbacks = @import("callbacks.zig");
const capabilities = @import("capabilities.zig");
const convert = @import("convert.zig");
const errors = @import("errors.zig");
const options_mod = @import("options.zig");
const snapshot_mod = @import("snapshot.zig");
const userdata_mod = @import("userdata.zig");
const BytecodeLoadOptions = options_mod.BytecodeLoadOptions;
const Context = @import("context.zig").Context;
const Coroutine = @import("coroutine.zig").Coroutine;
const DoOptions = options_mod.DoOptions;
const ErrorRef = errors.ErrorRef;
const ExitRequest = capabilities.ExitRequest;
const Function = @import("function.zig").Function;
const GcBudget = options_mod.GcBudget;
const GcMode = options_mod.GcMode;
const GcParam = options_mod.GcParam;
const GcStepResult = options_mod.GcStepResult;
const HostFn = callbacks.HostFn;
const InstructionBudget = options_mod.InstructionBudget;
const LoadMode = options_mod.LoadMode;
const LoadOptions = options_mod.LoadOptions;
const MemoryFile = capabilities.MemoryFile;
const MemoryFilesystem = capabilities.MemoryFilesystem;
const MemoryLimitAllocator = @import("memory_limit.zig").MemoryLimitAllocator;
const Options = options_mod.Options;
const RegisteredCallback = callbacks.RegisteredCallback;
const RollbackMetadata = snapshot_mod.RollbackMetadata;
const Snapshot = snapshot_mod.Snapshot;
const SnapshotBacking = snapshot_mod.SnapshotBacking;
const Stdlib = options_mod.Stdlib;
const Table = @import("table.zig").Table;
const TableOptions = options_mod.TableOptions;
const Userdata = userdata_mod.Userdata;
const UserdataOptions = userdata_mod.UserdataOptions;
const UserdataPtrOptions = userdata_mod.UserdataPtrOptions;
const Value = @import("value.zig").Value;
const coroutine_mod = @import("../runtime/coroutine.zig");
const entry_mod = @import("../runtime/entry.zig");
const io_mod = @import("../runtime/io.zig");
const load_mod = @import("../runtime/load.zig");

/// Copyable, thread-safe handle that stops Lua at the next safepoint with `error.Interrupted`.
/// Join threads using it before `State.deinit`. Lua cannot catch it and pending `__close`
/// handlers do not run. A request made while idle applies to the next execution.
pub const InterruptHandle = struct {
    control: *runtime.InterruptControl,

    pub fn interrupt(self: InterruptHandle) void {
        self.control.request();
    }

    pub fn isPending(self: InterruptHandle) bool {
        return self.control.isRequested();
    }
};

/// Owns a Lua VM and its host-facing API state.
pub const State = struct {
    base_allocator: std.mem.Allocator,
    /// Advances on successful reset; handles from prior generations are invalid.
    generation: u64 = 0,
    /// Active snapshot baseline; null before capture.
    baseline: ?*const SnapshotBacking = null,
    /// Owner of borrowed bytecode; capture may replace the active baseline.
    immutable_owner: ?*const SnapshotBacking = null,
    rollback_metadata: ?RollbackMetadata = null,
    /// Stable allocator wrapper; unlimited until a memory limit is set.
    memory_limit_allocator: ?*MemoryLimitAllocator = null,
    raw_state: runtime.State,
    /// Registry root for the last captured Lua error value.
    last_error_root: ?usize = null,
    /// Traceback captured with the last error by `Function.callWith`.
    last_error_traceback: ?[]u8 = null,
    /// Owned entries visible to the memory filesystem.
    memory_files: std.ArrayList(MemoryFile) = .empty,
    /// Whether each memory-file entry owns its contents slice.
    memory_file_owned_contents: std.ArrayList(bool) = .empty,
    callbacks: std.ArrayList(RegisteredCallback) = .empty,

    /// `state_allocator` must remain valid until `deinit`.
    pub fn init(state_allocator: std.mem.Allocator, options: Options) !State {
        inline for (reflection.fieldsOf(GcParam)) |f| try options_mod.validateGcParam(options.gc.params.get(@field(GcParam, f)));
        var memory_limit_allocator: ?*MemoryLimitAllocator = null;
        errdefer if (memory_limit_allocator) |allocator_ptr| state_allocator.destroy(allocator_ptr);

        const runtime_allocator = blk: {
            const allocator_ptr = try state_allocator.create(MemoryLimitAllocator);
            allocator_ptr.* = MemoryLimitAllocator.init(state_allocator, options.limits.max_memory orelse std.math.maxInt(usize));
            memory_limit_allocator = allocator_ptr;
            break :blk allocator_ptr.allocator();
        };

        var state = State{
            .base_allocator = state_allocator,
            .memory_limit_allocator = memory_limit_allocator,
            .raw_state = try runtime.State.initWithOptions(runtime_allocator, options_mod.runtimeOptions(options)),
        };
        state.raw_state.gc.mode = options.gc.mode;
        state.raw_state.gc.running = options.gc.running;
        state.raw_state.gc.params = options.gc.params;
        state.raw_state.gc.resetAutoThreshold();
        if (memory_limit_allocator) |limit| state.raw_state.allocator_lifetime = &limit.lifetime;
        memory_limit_allocator = null;
        errdefer state.deinit();

        if (options.capabilities.filesystem == .memory) {
            const files = options.capabilities.filesystem.memory;
            for (files) |file| try appendMemoryFile(&state, file.path, file.contents, false);
            state.raw_state.options.filesystem = .{ .memory = state.memory_files.items };
        }

        return state;
    }

    /// Runs pending finalizers like `lua_close` (errors ignored, open files flushed), then
    /// frees the state and invalidates all handles. `reset` runs no finalizers.
    pub fn deinit(self: *State) void {
        const state_allocator = self.allocator();
        if (self.last_error_traceback) |text| state_allocator.free(text);
        snapshot_mod.abandonRollbackMetadata(self);
        callbacks.bindDispatch(self);
        self.raw_state.deinit();
        deinitOwnedMemoryFiles(self, state_allocator);
        self.memory_files.deinit(state_allocator);
        self.memory_file_owned_contents.deinit(state_allocator);
        callbacks.deinitNames(self, state_allocator);
        self.callbacks.deinit(state_allocator);
        self.destroyMemoryLimitAllocator();
        if (self.baseline) |baseline| baseline.release();
        if (self.immutable_owner) |owner| owner.release();
        self.* = undefined;
    }

    /// Captures an idle VM, including suspended coroutines, as the new reset baseline.
    /// Borrowed capabilities and `snapshot_allocator` must outlive every state retaining it.
    pub fn snapshot(self: *State, snapshot_allocator: std.mem.Allocator) !Snapshot {
        return snapshot_mod.create(self, snapshot_allocator);
    }

    /// Restores the active baseline and invalidates prior handles; `error.NoSnapshot` without one.
    /// Fails atomically. Skips Lua `__gc` and `__close` handlers and discards file handles
    /// opened since the baseline without flushing them.
    pub fn reset(self: *State) !void {
        return snapshot_mod.reset(self);
    }

    /// Allocator for API-owned allocations returned to the host.
    pub fn allocator(self: *State) std.mem.Allocator {
        return self.raw_state.allocator;
    }

    pub fn instructionBudget(self: *const State) InstructionBudget {
        const used = self.raw_state.budget.used();
        const remaining = if (self.raw_state.options.max_instructions) |limit|
            if (used >= limit) 0 else limit - used
        else
            null;
        return .{
            .limit = self.raw_state.options.max_instructions,
            .used = used,
            .remaining = remaining,
        };
    }

    pub fn resetInstructionBudget(self: *State) void {
        self.raw_state.budget.reset();
    }

    /// Returns a thread-safe `InterruptHandle`; handles share one flag that stays valid across
    /// `reset` until `deinit`. While one exists, dispatch polls the flag periodically.
    pub fn interruptHandle(self: *State) !InterruptHandle {
        return .{ .control = try self.raw_state.budget.interruptControl() };
    }

    pub fn clearInterrupt(self: *State) void {
        self.raw_state.budget.clearInterrupt();
    }

    pub fn isInterruptPending(self: *const State) bool {
        return self.raw_state.budget.interruptRequested();
    }

    pub fn openLibs(self: *State, selection: Stdlib) !void {
        const runtime_selection = options_mod.toRuntimeStdlib(selection);
        try stdlib.openLibraries(&self.raw_state, runtime_selection);
        if (!runtime_selection.isEmpty()) try stdlib.installGlobalTable(&self.raw_state);
    }

    /// Runs a full collection and pending finalizers, even while automatic GC is stopped.
    pub fn collect(self: *State) !void {
        callbacks.bindDispatch(self);
        try self.raw_state.gc.collect();
    }

    /// Runs at most `budget.steps` basic steps, even while stopped; bounds work, not time.
    pub fn stepGc(self: *State, budget: GcBudget) !GcStepResult {
        callbacks.bindDispatch(self);
        return if (try self.raw_state.gc.runSteps(budget.steps)) .complete else .pending;
    }

    pub fn gcMode(self: *const State) GcMode {
        return self.raw_state.gc.mode;
    }

    /// Returns the previous mode.
    pub fn setGcMode(self: *State, mode: GcMode) GcMode {
        return self.raw_state.gc.setMode(mode);
    }

    pub fn gcParam(self: *const State, param: GcParam) i64 {
        return self.raw_state.gc.getParam(param);
    }

    /// Returns the previous value; values outside 0...maxInt(i32) return `error.InvalidGcParam`.
    pub fn setGcParam(self: *State, param: GcParam, value: i64) !i64 {
        try options_mod.validateGcParam(value);
        const previous = self.raw_state.gc.getParam(param);
        self.raw_state.gc.setParam(param, value);
        self.raw_state.gc.resetAutoThreshold();
        return previous;
    }

    pub fn stopGc(self: *State) void {
        self.raw_state.gc.running = false;
    }

    pub fn restartGc(self: *State) void {
        self.raw_state.gc.running = true;
    }

    pub fn isGcRunning(self: *const State) bool {
        return self.raw_state.gc.running;
    }

    /// Converts a Zig value into a rooted `Value`.
    pub fn push(self: *State, value: anytype) !Value {
        var result = try convert.fromRuntimeValue(self, try convert.toRuntimeValue(self, value), Value);
        errdefer result.deinit();
        try gcBoundary(self);
        return result;
    }

    /// A `[]const u8` result borrows VM memory; see `Value.string`.
    pub fn read(self: *State, value: Value, comptime T: type) !T {
        return convert.fromRuntimeValue(self, try convert.toRuntimeValue(self, value), T);
    }

    pub fn setGlobal(self: *State, name: []const u8, value: anytype) !void {
        const raw_name = try self.raw_state.strings.intern(name);
        const raw_value = try convert.toRuntimeValue(self, value);
        self.raw_state.putGlobal(raw_name, raw_value) catch |err| return errors.captureLuaError(self, err);
        try gcBoundary(self);
    }

    /// A `[]const u8` result borrows VM memory; see `Value.string`.
    pub fn getGlobal(self: *State, name: []const u8, comptime T: type) !T {
        return convert.fromRuntimeValue(self, self.raw_state.getGlobal(name), T);
    }

    /// Wraps an untyped callback as a Lua function; it is not installed automatically.
    pub fn register(self: *State, name: []const u8, callback: HostFn) !Function {
        return callbacks.create(self, name, callback);
    }

    /// Like `register`, reading parameters from Lua arguments by type; `*Context` is injected.
    pub fn registerTyped(self: *State, name: []const u8, comptime function: anytype) !Function {
        const Wrapper = struct {
            fn call(ctx: *Context) !void {
                try callbacks.callTyped(function, ctx);
            }
        };

        return self.register(name, Wrapper.call);
    }

    /// Registers a Lua constructor that reads `initializer`'s arguments by type (`*Context` is
    /// injected) and wraps its `T` or `!T` result with `newUserdataAuto`.
    pub fn registerUserdataInitializerWith(self: *State, comptime T: type, name: []const u8, comptime initializer: anytype, comptime options: UserdataOptions(T)) !Function {
        const Wrapper = struct {
            fn call(ctx: *Context) !void {
                try callbacks.callUserdataInitializer(T, initializer, options, ctx);
            }
        };

        return self.register(name, Wrapper.call);
    }

    pub fn createTable(self: *State, options: TableOptions) !Table {
        const raw = self.raw_state.newTableWithHints(options.array_hint, options.hash_hint) catch |err| return errors.captureLuaError(self, err);
        var table = try convert.fromRuntimeValue(self, raw, Table);
        errdefer table.deinit();
        try gcBoundary(self);
        return table;
    }

    /// Creates a suspended coroutine; first resume arguments become `entry`'s arguments.
    pub fn newCoroutine(self: *State, entry: Function) !Coroutine {
        const raw_entry = try convert.toRuntimeValue(self, entry);
        const raw = coroutine_mod.newCoroutineThread(&self.raw_state, raw_entry) catch |err| return errors.captureLuaError(self, err);
        var result = try convert.fromRuntimeValue(self, .{ .thread = raw }, Coroutine);
        errdefer result.deinit();
        try gcBoundary(self);
        return result;
    }

    /// Allocates Lua-owned userdata initialized with `value`.
    pub fn newUserdata(self: *State, comptime T: type, value: T, options: UserdataOptions(T)) !Userdata(T) {
        return userdata_mod.create(self, T, value, options);
    }

    /// Like `newUserdata`, also installing `T`'s methods whose receiver is `*T` or `*const T`;
    /// names starting with `__` become metamethods.
    pub fn newUserdataAuto(self: *State, comptime T: type, value: T, options: UserdataOptions(T)) !Userdata(T) {
        var userdata = try self.newUserdata(T, value, options);
        errdefer userdata.deinit();
        try userdata.bindMethods(T);
        return userdata;
    }

    /// Wraps host-owned `ptr` as userdata without taking ownership.
    pub fn newUserdataPtr(self: *State, comptime T: type, ptr: *T, options: UserdataPtrOptions(T)) !Userdata(T) {
        return userdata_mod.wrapPtr(self, T, ptr, options);
    }

    /// Like `newUserdataPtr`, also installing `T`'s methods as in `newUserdataAuto`.
    pub fn newUserdataPtrAuto(self: *State, comptime T: type, ptr: *T, options: UserdataPtrOptions(T)) !Userdata(T) {
        var userdata = try self.newUserdataPtr(T, ptr, options);
        errdefer userdata.deinit();
        try userdata.bindMethods(T);
        return userdata;
    }

    /// Creates a module table; it is not installed (see `setLoadedModule`).
    pub fn createModule(self: *State, name: []const u8) !Table {
        _ = name;
        return self.createTable(.{ .hash_hint = 4 });
    }

    /// Sets `package.loaded[name]` so `require(name)` returns `module`; opens `package` if needed.
    pub fn setLoadedModule(self: *State, name: []const u8, module: anytype) !void {
        var loaded = try self.packageField("loaded");
        defer loaded.deinit();
        try loaded.set(name, module);
    }

    /// Sets `package.preload[name]`, opening `package` if needed. The host keeps its `loader` handle.
    pub fn preloadModule(self: *State, name: []const u8, loader: Function) !void {
        var preload = try self.packageField("preload");
        defer preload.deinit();
        try preload.set(name, loader);
    }

    /// Registers `loader` like `registerTyped` and installs it with `preloadModule`.
    pub fn preloadModuleFn(self: *State, name: []const u8, comptime loader: anytype) !void {
        var function = try self.registerTyped(name, loader);
        defer function.deinit();
        try self.preloadModule(name, function);
    }

    /// Calls the built-in `require(name)`, opening `package` if needed, and converts the result.
    /// Loaders cannot yield; use `Tuple(&.{ M, []const u8 })` to also read the loader data.
    pub fn require(self: *State, name: []const u8, comptime T: type) !T {
        try self.ensurePackageLibrary();
        callbacks.bindDispatch(self);
        const raw_name = runtime.Value{ .string = try self.raw_state.strings.intern(name) };
        const results = entry_mod.callFunction(&self.raw_state, .{ .native = .require }, &.{raw_name}) catch |err| return errors.captureLuaError(self, err);
        defer self.allocator().free(results);
        return convert.fromRuntimeResults(self, results, T);
    }

    fn packageField(self: *State, name: []const u8) !Table {
        try self.ensurePackageLibrary();
        var package = try self.getGlobal("package", Table);
        defer package.deinit();
        return package.get(name, Table);
    }

    /// Sets `package.path`, opening the package library if needed.
    pub fn setPackagePath(self: *State, path: []const u8) !void {
        try self.ensurePackageLibrary();

        var package = try self.getGlobal("package", Table);
        defer package.deinit();
        try package.set("path", path);
    }

    /// Adds an owned copy to the memory filesystem, or writes through a writable one.
    /// Host and custom filesystems return `error.UnsupportedOption`.
    pub fn addMemoryFile(self: *State, path: []const u8, contents: []const u8) !void {
        self.raw_state.file_generation +%= 1;
        switch (self.raw_state.options.filesystem) {
            .disabled, .memory => {},
            .memory_rw => |filesystem| {
                try filesystem.writeFile(path, contents);
                return;
            },
            .host_cwd, .host_dir, .custom => return error.UnsupportedOption,
        }

        try appendMemoryFile(self, path, contents, true);
        self.raw_state.options.filesystem = .{ .memory = self.memory_files.items };
    }

    pub fn loadString(self: *State, source: []const u8, options: LoadOptions) !Function {
        const environment = try self.loadEnvironment(options);
        const loaded = self.loadBuffer(source, options.name, environment, options.mode) catch |err| return errors.captureLuaError(self, err);
        return convert.fromRuntimeValue(self, loaded, Function);
    }

    /// Loads through the configured filesystem capability.
    pub fn loadFile(self: *State, path: []const u8, options: LoadOptions) !Function {
        const source = io_mod.readFileAlloc(&self.raw_state, path) catch |err| return errors.captureLuaError(self, err);
        var keep_source = false;
        defer if (!keep_source) self.allocator().free(source);

        const allocated_source_name = if (options.name == null) try std.fmt.allocPrint(self.allocator(), "@{s}", .{path}) else null;
        defer if (allocated_source_name) |name| self.allocator().free(name);

        const environment = try self.loadEnvironment(options);
        const source_name = options.name orelse allocated_source_name.?;
        const loaded = self.loadBuffer(source, source_name, environment, options.mode) catch |err| return errors.captureLuaError(self, err);
        if (!looksLikeBinaryChunk(source)) {
            try self.raw_state.registerAllocation("source_allocations", source);
            keep_source = true;
        }
        return convert.fromRuntimeValue(self, loaded, Function);
    }

    pub fn loadBytecode(self: *State, bytecode: []const u8, options: BytecodeLoadOptions) !Function {
        const environment = try self.environmentValue(options.environment);
        const loaded = load_mod.loadBinaryDump(&self.raw_state, bytecode, environment) catch |err| return errors.captureLuaError(self, err);
        return convert.fromRuntimeValue(self, loaded, Function);
    }

    pub fn doString(self: *State, source: []const u8, options: DoOptions) !void {
        var function = try self.loadString(source, options);
        defer function.deinit();
        try function.call(.{}, void);
    }

    pub fn doFile(self: *State, path: []const u8, options: DoOptions) !void {
        var function = try self.loadFile(path, options);
        defer function.deinit();
        try function.call(.{}, void);
    }

    /// Exit recorded by `os.exit` after `error.LuaExit`, or null. `close` means Lua asked to
    /// close the state; pending to-be-closed variables have already run.
    pub fn exitRequest(self: *const State) ?ExitRequest {
        return self.raw_state.exit_request;
    }

    pub fn clearExitRequest(self: *State) void {
        self.raw_state.exit_request = null;
    }

    pub fn setWarnings(self: *State, on: bool) void {
        self.raw_state.warnings_on = on;
    }

    /// Formats the last Lua error; the caller frees the result with `allocator()`.
    pub fn errorMessage(self: *State) ![]const u8 {
        const value = errors.lastErrorValue(self);
        var out = std.ArrayList(u8).empty;
        defer out.deinit(self.allocator());
        try runtime.appendErrorValue(self.allocator(), &out, value);
        return self.allocator().dupe(u8, out.items);
    }

    /// Takes ownership of the last Lua error value; the caller must `deinit` it.
    pub fn takeErrorValue(self: *State) ?ErrorRef {
        const index = self.last_error_root orelse return null;
        self.last_error_root = null;
        const traceback_text = self.last_error_traceback;
        self.last_error_traceback = null;
        return .{ .ref = .{ .state = self, .generation = self.generation, .index = index }, .traceback_text = traceback_text };
    }

    fn loadEnvironment(self: *State, options: LoadOptions) !runtime.Value {
        return self.environmentValue(options.environment);
    }

    fn environmentValue(self: *State, environment: ?Table) !runtime.Value {
        return if (environment) |table| try convert.toRuntimeValue(self, table) else if (self.raw_state.global_table) |table| .{ .table = table } else self.raw_state.getGlobal("_G");
    }

    fn loadBuffer(self: *State, source: []const u8, source_name: ?[]const u8, environment: runtime.Value, mode: LoadMode) !runtime.Value {
        const binary = looksLikeBinaryChunk(source);
        switch (mode) {
            .source_only => if (binary) return self.raw_state.fail("attempt to load a binary chunk"),
            .binary_only => if (!binary) return self.raw_state.fail("attempt to load a text chunk"),
            .source_or_binary => {},
        }

        return if (binary)
            load_mod.loadBinaryDump(&self.raw_state, source, environment)
        else
            load_mod.loadSourceAsClosureNamedEnv(&self.raw_state, source, source_name, environment);
    }

    fn destroyMemoryLimitAllocator(self: *State) void {
        if (self.memory_limit_allocator) |allocator_ptr| {
            allocator_ptr.lifetime.release();
            self.memory_limit_allocator = null;
        }
    }

    fn ensurePackageLibrary(self: *State) !void {
        if (self.raw_state.getGlobal("package") == .nil) {
            try stdlib.openLibraries(&self.raw_state, .{ .libraries = .{ .package = true } });
        }
    }
};

// Called after embedding writes have installed all temporary values in roots.
pub fn gcBoundary(state: *State) !void {
    if (state.raw_state.gc.running and state.raw_state.gc.shouldRunAuto()) {
        _ = try state.raw_state.gc.runSteps(1);
    }
}

pub fn appendMemoryFile(state: *State, path: []const u8, contents: []const u8, owned_contents: bool) !void {
    try snapshot_mod.writableBindings(state);
    const normalized_path = try MemoryFilesystem.normalizePathAlloc(state.allocator(), path, MemoryFilesystem.default_max_path_len);
    errdefer state.allocator().free(normalized_path);
    const stored_contents = if (owned_contents) try state.allocator().dupe(u8, contents) else contents;
    errdefer if (owned_contents) state.allocator().free(stored_contents);

    try state.memory_files.ensureUnusedCapacity(state.allocator(), 1);
    try state.memory_file_owned_contents.ensureUnusedCapacity(state.allocator(), 1);
    state.memory_files.appendAssumeCapacity(.{ .path = normalized_path, .contents = stored_contents });
    state.memory_file_owned_contents.appendAssumeCapacity(owned_contents);
}

pub fn deinitOwnedMemoryFiles(state: *State, state_allocator: std.mem.Allocator) void {
    for (state.memory_files.items, 0..) |file, index| {
        state_allocator.free(file.path);
        if (state.memory_file_owned_contents.items[index]) state_allocator.free(file.contents);
    }
}

fn looksLikeBinaryChunk(source: []const u8) bool {
    return (source.len > 0 and source[0] == 0x1b) or
        std.mem.startsWith(u8, source, runtime.binary_chunk_signature) or
        (source.len > 0 and std.mem.startsWith(u8, runtime.binary_chunk_signature, source));
}

comptime {
    @setEvalBranchQuota(1000000);
    snapshot_runtime.review(State, .{
        .external = "base_allocator memory_limit_allocator baseline immutable_owner rollback_metadata",
        .rebuilt = "generation last_error_root last_error_traceback",
        .copied = "raw_state memory_files memory_file_owned_contents callbacks",
    });
    snapshot_runtime.review(runtime.StateOptions, .{
        .copied = "stdlib stdin stdout_flush stderr_flush capture_output warnings max_file_bytes max_memory max_stack_values max_call_frames max_instructions debug_errors trace_vm",
        .external = "io stdout stderr stdin_reader warning_handler filesystem environment clock process",
    });
}
