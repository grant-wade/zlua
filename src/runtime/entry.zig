const compile = @import("../compile.zig");
const errors = @import("../errors.zig");
const budget_mod = @import("budget.zig");
const call_mod = @import("call.zig");
const coroutine_mod = @import("coroutine.zig");
const debug_mod = @import("debug.zig");
const host = @import("host.zig");
const load_mod = @import("load.zig");
const state_mod = @import("state.zig");
const system_mod = @import("system.zig");
const types = @import("types.zig");
const upvalue_mod = @import("upvalue.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const State = state_mod.State;
const bytecode = compile.bytecode;
const proto_mod = compile.proto;
const Value = types.Value;
const ProtectedCallResult = types.ProtectedCallResult;
const Closure = types.Closure;
const Thread = types.Thread;
const HostErrorHandler = state_mod.HostErrorHandler;

/// Stack capacity above which a finished host thread is freed instead of kept for the next call.
const max_idle_stack_values = 4096;

pub fn execute(self: *State, proto: *proto_mod.Proto) !void {
    try value_mod.prepareProtoTree(proto);
    try executeClosure(self, try load_mod.newRootClosure(self, proto), .{ .host_frame = true });
}

// Heap-allocated so coroutine.running() can expose a stable identity; unexposed ones are released after the call.
pub fn newHostThread(self: *State, closure: *Closure) !*Thread {
    const thread = self.idle_host_thread orelse fresh: {
        const fresh = try self.allocator.create(Thread);
        fresh.* = .{};
        break :fresh fresh;
    };
    self.idle_host_thread = null;
    errdefer {
        thread.deinit(self.allocator);
        self.allocator.destroy(thread);
    }
    try thread.startRoot(self.allocator, closure, self.stackValueLimit());
    try self.registerAllocation("thread_allocations", thread);
    self.gc.noteAllocation(@sizeOf(Thread));
    return thread;
}

pub fn retireHostThread(self: *State, thread: *Thread) void {
    self.gc.syncThreadStorage(thread);
    upvalue_mod.closeUpvalues(self, thread, 0);
    if (!thread.exposed) {
        const index = thread.gc.registry_index;
        self.gc.forgetThread(thread);
        self.gc.removeRegistryItem("thread_allocations", index);
        self.gc.noteAllocationFreed(@sizeOf(Thread) + thread.storage_bytes);
        if (self.idle_host_thread != null or thread.rollback != null or thread.stack.capacity > max_idle_stack_values) return self.gc.destroyThread(thread);
        thread.recycle(self.allocator);
        self.idle_host_thread = thread;
        return;
    }
    // Drop storage borrowed from the host stack, keeping the observable thread and its hook.
    const retained = Thread{
        .gc = thread.gc,
        .storage_bytes = thread.storage_bytes,
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
    self.gc.syncThreadStorage(thread);
}

pub fn callLoadedClosure(self: *State, closure: *Closure, args: []const Value) ![]Value {
    return callLoadedClosureHandled(self, closure, args, .{}, &.{});
}

/// Like `callLoadedClosure`; `handler` runs at the error point before frames unwind, and results
/// that fit are returned in `buffer`.
fn callLoadedClosureHandled(self: *State, closure: *Closure, args: []const Value, handler: HostErrorHandler, buffer: []Value) ![]Value {
    const thread = newHostThread(self, closure) catch |err| switch (err) {
        error.StackOverflow => return self.fail("stack overflow"),
        else => return err,
    };
    defer retireHostThread(self, thread);
    try load_mod.setRootThreadArgs(self, thread, args);
    thread.frames.items[0].return_count = bytecode.multret_count;
    installHostErrorHandler(thread, handler);
    const previous_thread = self.current_thread;
    self.current_thread = thread;
    defer self.current_thread = previous_thread;
    vm_mod.runThreadUntil(self, thread, 0) catch |err| {
        try unwindHostThread(self, thread, err, handler);
        return err;
    };
    thread.status = .dead;
    const count = thread.last_result_count;
    if (count > buffer.len) return coroutine_mod.copyStackSlice(self, thread, thread.last_result_base, count);
    self.budget.note(budget_mod.cost.registers(count));
    @memcpy(buffer[0..count], thread.stack.items[thread.last_result_base..][0..count]);
    return buffer[0..count];
}

/// Like `protectedCallLoadedClosure`; `handler` runs at the error point before frames unwind.
fn protectedCallLoadedClosureHandled(self: *State, closure: *Closure, args: []const Value, handler: HostErrorHandler) !ProtectedCallResult {
    const thread = newHostThread(self, closure) catch |err| switch (err) {
        error.StackOverflow => return .{ .failure = .{ .string = try self.strings.intern("stack overflow") } },
        else => return err,
    };
    defer retireHostThread(self, thread);
    try load_mod.setRootThreadArgs(self, thread, args);
    thread.frames.items[0].return_count = bytecode.multret_count;
    installHostErrorHandler(thread, handler);
    const previous_thread = self.current_thread;
    self.current_thread = thread;
    defer self.current_thread = previous_thread;

    self.last_error = null;
    vm_mod.runThreadUntil(self, thread, 0) catch |err| switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => {
            call_mod.noteCaughtError(self, err);
            if (self.options.debug_errors) debug_mod.appendUnhandledErrorDebugDump(self, thread, err) catch {};
            applyHostErrorHandler(self, thread, handler) catch |handler_err| {
                thread.status = .dead;
                return handler_err;
            };
            var failure = self.currentErrorValue();
            upvalue_mod.closeFramesTo(self, thread, 0, failure) catch |close_err| switch (close_err) {
                error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => failure = self.currentErrorValue(),
                else => return close_err,
            };
            thread.status = .dead;
            return .{ .failure = failure };
        },
        error.LuaExit => {
            try system_mod.finishExitUnwind(self, thread);
            thread.status = .dead;
            return err;
        },
        else => {
            thread.status = .dead;
            return err;
        },
    };
    thread.status = .dead;
    return .{ .success = try coroutine_mod.copyStackSlice(self, thread, thread.last_result_base, thread.last_result_count) };
}

pub fn callFunction(self: *State, function: Value, args: []const Value) ![]Value {
    return callFunctionHandled(self, function, args, .{});
}

/// Like `callFunction`; `handler` runs at the error point before frames unwind.
pub fn callFunctionHandled(self: *State, function: Value, args: []const Value, handler: HostErrorHandler) ![]Value {
    return callFunctionInto(self, function, args, handler, &.{});
}

/// Like `callFunctionHandled`; the results are in `buffer` if the returned slice starts there, and
/// otherwise in a slice the caller frees.
pub fn callFunctionInto(self: *State, function: Value, args: []const Value, handler: HostErrorHandler, buffer: []Value) ![]Value {
    if (function == .closure) return callLoadedClosureHandled(self, function.closure, args, handler, buffer);
    // A native callee still needs a frame for arguments, errors, and reentrant Lua calls.
    var proto = proto_mod.Proto.init(self.allocator);
    defer proto.deinit();
    proto.source_name = "=[C]";
    var closure = Closure{ .proto = &proto };
    const thread = newHostThread(self, &closure) catch |err| switch (err) {
        error.StackOverflow => return self.fail("stack overflow"),
        else => return err,
    };
    defer retireHostThread(self, thread);
    installHostErrorHandler(thread, handler);
    const previous_thread = self.current_thread;
    self.current_thread = thread;
    defer self.current_thread = previous_thread;
    self.last_error = null;
    return call_mod.callCollect(self, thread, function, args) catch |err| {
        if (err == error.Interrupted and self.execution_depth == 0) self.budget.consumeInterrupt();
        try unwindHostThread(self, thread, err, handler);
        return err;
    };
}

/// Like `protectedCallFunction`; `handler` runs at the error point before frames unwind.
pub fn protectedCallFunctionHandled(self: *State, function: Value, args: []const Value, handler: HostErrorHandler) !ProtectedCallResult {
    if (function == .closure) return protectedCallLoadedClosureHandled(self, function.closure, args, handler);
    const values = callFunctionHandled(self, function, args, handler) catch |err| switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => return .{ .failure = self.currentErrorValue() },
        else => return err,
    };
    return .{ .success = values };
}

pub fn executeSourceChunk(self: *State, source: []const u8) !void {
    const loaded = try load_mod.loadSourceAsClosure(self, source);
    try executeClosure(self, loaded.closure, .{});
}

pub fn executeSourceChunkNamed(self: *State, source: []const u8, source_name: []const u8) !void {
    return executeSourceChunkNamedHandled(self, source, source_name, .{});
}

/// Like `executeSourceChunkNamed`; `handler` runs at a runtime error point before frames unwind.
pub fn executeSourceChunkNamedHandled(self: *State, source: []const u8, source_name: []const u8, handler: HostErrorHandler) !void {
    const loaded = try load_mod.loadSourceAsClosureNamed(self, source, source_name);
    try executeClosure(self, loaded.closure, handler);
}

fn executeClosure(self: *State, closure: *Closure, handler: HostErrorHandler) !void {
    const thread = newHostThread(self, closure) catch |err| switch (err) {
        error.StackOverflow => return self.fail("stack overflow"),
        else => return err,
    };
    defer retireHostThread(self, thread);
    installHostErrorHandler(thread, handler);
    const previous_thread = self.current_thread;
    self.current_thread = thread;
    defer self.current_thread = previous_thread;
    vm_mod.runThreadUntil(self, thread, 0) catch |err| {
        try unwindHostThread(self, thread, err, handler);
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
    if (err == error.LuaExit) return system_mod.finishExitUnwind(self, thread);
    if (err == error.Interrupted) return;
    call_mod.noteCaughtError(self, err);
    if (self.options.debug_errors and call_mod.isRuntimeError(err)) debug_mod.appendUnhandledErrorDebugDump(self, thread, err) catch {};
    if (call_mod.isRuntimeError(err)) try applyHostErrorHandler(self, thread, handler);
    try upvalue_mod.closeFramesTo(self, thread, 0, self.currentErrorValue());
}

fn applyHostErrorHandler(self: *State, thread: *Thread, handler: HostErrorHandler) !void {
    if (handler.traceback) |out| {
        if (out.*) |previous| self.allocator.free(previous);
        out.* = null;
        out.* = try debug_mod.formatTraceback(self, thread, handler.host_frame);
    }
    if (thread.frames.items.len != 0) try call_mod.applyMessageHandler(self, thread);
}
