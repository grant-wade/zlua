const std = @import("std");
const compile = @import("../compile.zig");
const call_mod = @import("call.zig");
const debug_mod = @import("debug.zig");
const host = @import("host.zig");
const State = @import("state.zig").State;
const types = @import("types.zig");
const upvalue_mod = @import("upvalue.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const bytecode = compile.bytecode;
const proto_mod = compile.proto;
const Value = types.Value;
const CoroutineResumeResult = types.CoroutineResumeResult;
const Closure = types.Closure;
const Upvalue = types.Upvalue;
const Thread = types.Thread;
const ThreadStatus = types.ThreadStatus;
const argValue = value_mod.argValue;
const functionLike = value_mod.functionLike;

fn freeCoroutineResumeResult(allocator: std.mem.Allocator, result: CoroutineResumeResult) void {
    switch (result) {
        .success => |values| allocator.free(values),
        .failure => {},
    }
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

pub fn coroutineCreate(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const entry = argValue(self, thread, op, 0);
    if (!functionLike(entry)) return self.failArgumentType("coroutine.create", 1, "function", entry);
    try self.returnValues(thread, op.base, op.return_count, &.{.{ .thread = try newCoroutineThread(self, entry) }});
}

pub fn coroutineResume(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const target = try self.expectArgumentThread(thread, op, "coroutine.resume", 0);
    const args = try call_mod.collectArgs(self, thread, op, 1);
    defer self.allocator.free(args);

    const result = try resumeCoroutine(self, target, args);
    defer freeCoroutineResumeResult(self.allocator, result);
    try returnCoroutineResumeResult(self, thread, op.base, op.return_count, result);
}

// Both coroutine.yield and an API callback contribute one native frame.
pub fn isYieldable(thread: *const Thread) bool {
    return !thread.is_main and thread.status == .running and !thread.closing and thread.native_call_depth <= 1;
}

/// Returns the Lua error message for a yield from `thread`, or null when it can yield.
pub fn yieldRejection(thread: *const Thread) ?[]const u8 {
    if (isYieldable(thread)) return null;
    if (thread.is_main) return "attempt to yield from outside a coroutine";
    if (thread.closing) return "attempt to yield from a __close metamethod";
    return "attempt to yield across a native-call boundary";
}

fn checkYieldable(self: *State, thread: *const Thread) !void {
    if (yieldRejection(thread)) |message| return self.fail(message);
}

/// Marks `thread` as reachable from a Lua value so it outlives its host call.
pub fn exposeThread(thread: *Thread) !void {
    try @import("rollback.zig").threadWritable(thread);
    thread.exposed = true;
}

pub fn suspendCoroutine(self: *State, thread: *Thread, op: bytecode.Call, values: []const Value) !void {
    try checkYieldable(self, thread);
    try @import("rollback.zig").threadWritable(thread);
    // Commit suspension only after storage is available.
    try thread.yield_values.ensureTotalCapacity(self.allocator, values.len);
    thread.yield_values.clearRetainingCapacity();
    thread.yield_values.appendSliceAssumeCapacity(values);
    for (values) |value| self.gc.threadBarrier(thread, value);
    self.gc.rememberObject(.{ .thread = thread });
    const frame = thread.frames.items[thread.frames.items.len - 1];
    thread.yield_result_base = frame.base + op.base;
    thread.yield_result_count = op.return_count;
    if (thread.hook_return and !thread.hook_running) thread.pending_yield_hook_return = true;
    thread.status = .suspended;
    return error.CoroutineYield;
}

pub fn coroutineYield(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const base = thread.frames.items[thread.frames.items.len - 1].base + op.base + 1;
    return suspendCoroutine(self, thread, op, thread.stack.items[base .. base + op.arg_count]);
}

pub fn coroutineStatus(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const target = try self.expectArgumentThread(thread, op, "coroutine.status", 0);
    try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.strings.intern(threadStatusName(target.status)) }});
}

pub fn coroutineRunning(self: *State, thread: *Thread, op: bytecode.Call) !void {
    try exposeThread(thread);
    try self.returnValues(thread, op.base, op.return_count, &.{ .{ .thread = thread }, .{ .boolean = thread.is_main } });
}

pub fn coroutineIsYieldable(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const target = if (op.arg_count == 0) thread else try self.expectArgumentThread(thread, op, "coroutine.isyieldable", 0);
    const yieldable = if (target == thread)
        isYieldable(thread)
    else
        !target.is_main and target.status != .dead and !target.closing;
    try self.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = yieldable }});
}

pub fn coroutineClose(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const target = if (op.arg_count == 0) thread else try self.expectArgumentThread(thread, op, "coroutine.close", 0);
    if (target.closing) return self.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
    const closes_self = target == thread and target.status == .running;
    if (try closeCoroutine(self, target, null)) |error_value| {
        if (closes_self) return self.throwValue(error_value);
        try self.returnValues(thread, op.base, op.return_count, &.{ .{ .boolean = false }, error_value });
        return;
    }
    if (closes_self) return error.CoroutineClose;
    try self.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn coroutineWrap(self: *State, thread: *Thread, op: bytecode.Call) !void {
    if (argValue(self, thread, op, 0) == .gmatch_iterator) {
        try self.returnValues(thread, op.base, op.return_count, &.{argValue(self, thread, op, 0)});
        return;
    }
    const entry = argValue(self, thread, op, 0);
    if (!functionLike(entry)) return self.failArgumentType("coroutine.wrap", 1, "function", entry);
    try self.returnValues(thread, op.base, op.return_count, &.{.{ .coroutine_wrapper = try newCoroutineThread(self, entry) }});
}

pub fn callCoroutineWrapper(self: *State, thread: *Thread, op: bytecode.Call, target: *Thread) !void {
    const args = try call_mod.collectArgs(self, thread, op, 0);
    defer self.allocator.free(args);
    try callCoroutineWrapperWithArgs(self, thread, op.base, op.return_count, target, args);
}

fn callCoroutineWrapperWithArgs(self: *State, thread: *Thread, base: u32, return_count: u16, target: *Thread, args: []const Value) !void {
    const result = try resumeCoroutine(self, target, args);
    defer freeCoroutineResumeResult(self.allocator, result);
    switch (result) {
        .success => |values| try self.returnValues(thread, base, return_count, values),
        .failure => |error_value| {
            const failure = if (target.status == .dead)
                (try closeCoroutine(self, target, null)) orelse error_value
            else
                error_value;
            return self.throwValue(try self.withLibraryWhere(failure));
        },
    }
}

pub fn newCoroutineThread(self: *State, entry: Value) !*Thread {
    const thread = try self.allocator.create(Thread);
    errdefer self.allocator.destroy(thread);
    thread.* = Thread.initCoroutine(entry);
    errdefer thread.deinit(self.allocator);
    try self.registerAllocation("thread_allocations", thread);
    self.gc.noteAllocation(@sizeOf(Thread));
    return thread;
}

/// The running thread may close itself; hosts are rejected earlier by `State.closeCoroutine`.
fn closeCoroutine(self: *State, target: *Thread, error_value: ?Value) !?Value {
    if (target.status == .normal) return self.fail("cannot close a normal coroutine");
    if (target.is_main) return self.fail("cannot close main coroutine");
    if (target.status == .running and target != self.current_thread) return self.fail("cannot close a running coroutine");
    try @import("rollback.zig").threadWritable(target);
    if (self.coroutine_close_depth >= State.max_c_calls) return .{ .string = try self.strings.intern("C stack overflow") };
    self.coroutine_close_depth += 1;
    defer self.coroutine_close_depth -= 1;

    const previous_thread = self.current_thread;
    const previous_parent = target.resume_parent;
    self.current_thread = target;
    if (previous_thread != target) target.resume_parent = previous_thread;
    target.status = .running;
    target.closing = true;
    defer {
        target.closing = false;
        target.status = .dead;
        target.resume_parent = previous_parent;
        self.current_thread = previous_thread;
    }

    const failure = error_value orelse target.close_error_value;
    defer target.close_error_value = null;
    target.error_handler = .nil;
    upvalue_mod.closeFramesTo(self, target, 0, failure) catch |err| switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => return try call_mod.caughtErrorValue(self, self.currentErrorValue()),
        else => return err,
    };
    return failure;
}

pub fn resumeCoroutine(self: *State, target: *Thread, args: []const Value) !CoroutineResumeResult {
    if (target.is_main) return .{ .failure = .{ .string = try self.strings.intern("cannot resume main coroutine") } };
    if (target.status == .dead) return .{ .failure = .{ .string = try self.strings.intern("cannot resume dead coroutine") } };
    if (target.status != .suspended) return .{ .failure = .{ .string = try self.strings.intern("cannot resume non-suspended coroutine") } };

    const parent = self.current_thread;
    if (parent == target) return .{ .failure = .{ .string = try self.strings.intern("cannot resume running coroutine") } };
    if (resumeChainDepth(parent) >= State.max_c_calls) return .{ .failure = .{ .string = try self.strings.intern("C stack overflow") } };

    try @import("rollback.zig").threadWritable(target);
    if (parent) |parent_thread| {
        if (parent_thread.status == .running) parent_thread.status = .normal;
    }
    const previous_thread = self.current_thread;
    const previous_parent = target.resume_parent;
    self.current_thread = target;
    target.resume_parent = parent;
    target.status = .running;
    errdefer target.status = .dead;
    defer {
        self.current_thread = previous_thread;
        target.resume_parent = previous_parent;
        if (parent) |parent_thread| {
            if (parent_thread.status == .normal) parent_thread.status = .running;
        }
    }

    self.last_error = null;
    var first = true;
    while (true) {
        const execution = if (first) beginResume(self, target, args) else vm_mod.runThreadUntil(self, target, 0);
        first = false;
        execution catch |err| switch (err) {
            error.CoroutineYield => return .{ .success = try copyValues(self, target.yield_values.items) },
            error.CoroutineClose => return .{ .success = try copyValues(self, &.{}) },
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode, error.OutOfMemory => {
                call_mod.noteCaughtError(self, err);
                const completed = call_mod.completeProtectedContinuationError(self, target) catch |continuation_err| switch (continuation_err) {
                    error.CoroutineYield => return .{ .success = try copyValues(self, target.yield_values.items) },
                    else => return continuation_err,
                };
                if (completed) continue;
                const error_value = try call_mod.caughtErrorValue(self, self.currentErrorValue());
                target.error_traceback = try debug_mod.snapshotCoroutineErrorTraceback(self, target);
                target.close_error_value = error_value;
                self.gc.threadBarrier(target, error_value);
                target.status = .dead;
                return .{ .failure = error_value };
            },
            error.Interrupted => {
                upvalue_mod.closeUpvalues(self, target, 0);
                return err;
            },
            else => return err,
        };
        break;
    }

    target.status = .dead;
    target.close_error_value = null;
    target.error_traceback = null;
    if (target.entry == .native and target.entry.native == .dofile and target.last_result_count >= 2) {
        const values = target.stack.items[target.last_result_base .. target.last_result_base + target.last_result_count];
        if (values[0] == .native and values[0].native == .dofile and values[1] == .string) {
            return .{ .success = try copyValues(self, values[2..]) };
        }
    }
    return .{ .success = try copyStackSlice(self, target, target.last_result_base, target.last_result_count) };
}

fn beginResume(self: *State, target: *Thread, args: []const Value) !void {
    if (!target.started) {
        try startCoroutine(self, target, args);
    } else {
        try setCoroutineResumeValues(self, target, args);
    }
    for (args) |value| self.gc.threadBarrier(target, value);
    try vm_mod.runThreadUntil(self, target, 0);
}

fn startCoroutine(self: *State, target: *Thread, args: []const Value) !void {
    try @import("rollback.zig").threadWritable(target);
    const closure, const arg_count = switch (target.entry) {
        .closure => |closure| blk: {
            try target.ensureStack(self.allocator, 1 + args.len, call_mod.callStackValueLimit(self, target));
            target.stack.items[0] = .{ .closure = closure };
            for (args, 0..) |arg, index| target.stack.items[1 + index] = arg;
            break :blk .{ closure, args.len };
        },
        else => blk: {
            const trampoline = try callableEntryClosure(self);
            try target.ensureStack(self.allocator, 2 + args.len, call_mod.callStackValueLimit(self, target));
            target.stack.items[0] = .{ .closure = trampoline };
            target.stack.items[1] = target.entry;
            for (args, 0..) |arg, index| target.stack.items[2 + index] = arg;
            break :blk .{ trampoline, 1 + args.len };
        },
    };
    var frame = try call_mod.prepareClosureFrame(self, target, closure, 0, 0, arg_count, 0, bytecode.multret_count);
    errdefer target.releaseFrame(&frame, self.allocator);
    try target.frames.append(self.allocator, frame);
    target.started = true;
    if (target.hook_call and !target.hook_running) try debug_mod.callHook(self, target, "call");
}

fn callableEntryClosure(self: *State) !*Closure {
    const proto = try self.allocator.create(proto_mod.Proto);
    errdefer self.allocator.destroy(proto);
    proto.* = proto_mod.Proto.init(self.allocator);
    errdefer proto.deinit();
    proto.max_registers = 2;
    proto.param_count = 1;
    proto.is_vararg = true;
    proto.source_name = @import("debug.zig").coroutine_entry_source;
    _ = try proto.emit(.{ .vararg = .{ .dest = 1, .count = bytecode.multret_count } }, 0);
    _ = try proto.emit(.{ .call = .{ .base = 0, .arg_count = bytecode.multret_arg_count, .return_count = bytecode.multret_count } }, 0);
    _ = try proto.emit(.{ .ret = .{ .first = 0, .count = bytecode.multret_count } }, 0);
    try self.registerAllocation("proto_allocations", proto);
    errdefer {
        _ = self.proto_allocations.pop();
        if (self.rollback) |journal| journal.freed(@intFromPtr(proto));
    }

    const upvalues = try self.allocator.alloc(*Upvalue, 0);
    errdefer self.allocator.free(upvalues);
    const closure = try self.allocator.create(Closure);
    closure.* = .{ .proto = proto, .upvalues = upvalues };
    errdefer self.allocator.destroy(closure);
    try self.registerAllocation("closure_allocations", closure);
    self.gc.noteAllocation(@sizeOf(Closure));
    return closure;
}

fn setCoroutineResumeValues(self: *State, target: *Thread, args: []const Value) !void {
    try @import("rollback.zig").threadWritable(target);
    const actual_count = try call_mod.resolveReturnCount(self, target.yield_result_count, args.len);
    try target.ensureStack(self.allocator, target.yield_result_base + actual_count, call_mod.callStackValueLimit(self, target));
    for (0..actual_count) |index| {
        target.stack.items[target.yield_result_base + index] = if (index < args.len) args[index] else .nil;
    }
    target.last_result_base = target.yield_result_base;
    target.last_result_count = actual_count;
}

fn returnCoroutineResumeResult(self: *State, thread: *Thread, base: u32, return_count: u16, result: CoroutineResumeResult) !void {
    switch (result) {
        .success => |values| {
            var returns = std.ArrayList(Value).empty;
            defer returns.deinit(self.allocator);
            try returns.append(self.allocator, .{ .boolean = true });
            try returns.appendSlice(self.allocator, values);
            try self.returnValues(thread, base, return_count, returns.items);
        },
        .failure => |error_value| try self.returnValues(thread, base, return_count, &.{ .{ .boolean = false }, error_value }),
    }
}

fn copyValues(self: *State, values: []const Value) ![]Value {
    const copied = try self.allocator.alloc(Value, values.len);
    @memcpy(copied, values);
    return copied;
}

pub fn copyStackSlice(self: *State, thread: *Thread, base: usize, count: usize) ![]Value {
    const values = try self.allocator.alloc(Value, count);
    for (values, 0..) |*value, index| value.* = thread.stack.items[base + index];
    return values;
}

pub fn closeCoroutineFromHost(self: *State, target: *Thread, error_value: ?Value) !?Value {
    if (target.status == .running and !target.is_main) return self.fail("cannot close a running coroutine");
    return closeCoroutine(self, target, error_value);
}
