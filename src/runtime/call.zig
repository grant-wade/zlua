const std = @import("std");
const compile = @import("../compile.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const bytecode = compile.bytecode;
const proto_mod = compile.proto;

const RuntimeErrorPayload = types.RuntimeErrorPayload;
const Value = types.Value;
const ProtectedCallResult = types.ProtectedCallResult;
const ProtectedCallContext = types.ProtectedCallContext;
const ProtectedContinuation = types.ProtectedContinuation;
const CallOneContinuationResult = types.CallOneContinuationResult;
const CallOneContinuation = types.CallOneContinuation;
const Closure = types.Closure;
const Thread = types.Thread;
const CallFrame = types.CallFrame;

const freeProtectedResult = value_mod.freeProtectedResult;
const argValue = value_mod.argValue;
const truthy = value_mod.truthy;

pub fn callOneResult(comptime State: type, self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!Value {
    return callOneResultMaybeContinuation(State, self, thread, callable, args, null);
}

pub fn callOneResultWithContinuation(comptime State: type, self: *State, thread: *Thread, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value {
    return callOneResultMaybeContinuation(State, self, thread, callable, args, result);
}

pub fn callOneMetamethodWithContinuation(comptime State: type, self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value {
    const previous_name = thread.next_call_name;
    const previous_namewhat = thread.next_call_namewhat;
    thread.next_call_name = metamethodDebugName(name);
    thread.next_call_namewhat = "metamethod";
    defer {
        thread.next_call_name = previous_name;
        thread.next_call_namewhat = previous_namewhat;
    }
    return callOneResultWithContinuation(State, self, thread, callable, args, result);
}

pub fn callOneMetamethod(comptime State: type, self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value) anyerror!Value {
    return callOneNamed(State, self, thread, metamethodDebugName(name), "metamethod", callable, args);
}

/// Calls `callable` for one result; a Lua callee reports `namewhat 'name'`.
pub fn callOneNamed(comptime State: type, self: *State, thread: *Thread, name: []const u8, namewhat: []const u8, callable: Value, args: []const Value) anyerror!Value {
    const previous_name = thread.next_call_name;
    const previous_namewhat = thread.next_call_namewhat;
    thread.next_call_name = name;
    thread.next_call_namewhat = namewhat;
    defer {
        thread.next_call_name = previous_name;
        thread.next_call_namewhat = previous_namewhat;
    }
    return callOneResult(State, self, thread, callable, args);
}

pub fn metamethodDebugName(name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, name, "__")) name[2..] else name;
}

pub fn callOneResultMaybeContinuation(comptime State: type, self: *State, thread: *Thread, callable: Value, args: []const Value, continuation_result: ?CallOneContinuationResult) anyerror!Value {
    const frame_count = thread.frames.items.len;
    const relative_base = thread.scratchRegister();
    const base = thread.frames.items[frame_count - 1].base + @as(usize, relative_base);
    try thread.ensureStack(self.allocator, base + 1 + args.len, self.callStackValueLimit(thread));
    thread.stack.items[base] = callable;
    for (args, 0..) |arg, index| thread.stack.items[base + 1 + index] = arg;

    self.invokeValue(thread, .{ .base = relative_base, .arg_count = @intCast(args.len), .return_count = 1 }, 0) catch |err| switch (err) {
        error.CoroutineYield => {
            if (continuation_result) |result| try pushCallOneContinuation(State, self, thread, frame_count, result);
            return err;
        },
        else => return err,
    };
    self.runThreadUntil(thread, frame_count) catch |err| switch (err) {
        error.CoroutineYield => {
            if (continuation_result) |result| try pushCallOneContinuation(State, self, thread, frame_count, result);
            return err;
        },
        else => return err,
    };
    return thread.stack.items[base];
}

pub fn pushCallOneContinuation(comptime State: type, self: *State, thread: *Thread, frame_count: usize, result: CallOneContinuationResult) !void {
    try thread.call_one_continuations.append(self.allocator, .{ .frame_count = frame_count, .result = result });
    thread.noteContinuation(frame_count);
}

pub fn readyCallOneContinuationIndex(thread: *Thread) ?usize {
    for (thread.call_one_continuations.items, 0..) |continuation, index| {
        if (continuation.frame_count == thread.frames.items.len) return index;
    }
    return null;
}

pub fn completeReadyCallOneContinuation(comptime State: type, self: *State, thread: *Thread) !bool {
    const index = readyCallOneContinuationIndex(thread) orelse return false;
    const continuation = thread.call_one_continuations.orderedRemove(index);
    thread.refreshContinuationFrameCount();
    const value = if (thread.last_result_count == 0) Value.nil else thread.stack.items[thread.last_result_base];
    switch (continuation.result) {
        .value => |dest| thread.stack.items[dest] = value,
        .truthy => |dest| thread.stack.items[dest] = .{ .boolean = truthy(value) },
        .inverted_truthy => |dest| thread.stack.items[dest] = .{ .boolean = !truthy(value) },
        .branch_truthy => |branch| {
            thread.last_result_count = 0;
            thread.last_transfer_count = 0;
            try self.jumpIfBranchResult(thread, truthy(value), branch.jump_if_truthy, branch.offset);
        },
        .branch_inverted_truthy => |branch| {
            thread.last_result_count = 0;
            thread.last_transfer_count = 0;
            try self.jumpIfBranchResult(thread, !truthy(value), branch.jump_if_truthy, branch.offset);
        },
        .concat => |pending| {
            thread.stack.items[pending.first + pending.count - 1] = value;
            try self.finishConcatRange(thread, pending.dest, pending.first, pending.count);
        },
        .discard => {},
    }
    return true;
}

pub fn protectedCall(comptime State: type, self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!ProtectedCallResult {
    const context = protectedCallContextWithErrors(State, self, thread);
    return runProtectedCall(State, self, thread, context, callable, args);
}

pub fn protectedCallContext(comptime State: type, _: *State, thread: *Thread) ProtectedCallContext {
    const frame_count = thread.frames.items.len;
    const relative_base = thread.scratchRegister();
    return .{
        .frame_count = frame_count,
        .relative_base = relative_base,
        .absolute_base = thread.frames.items[frame_count - 1].base + @as(usize, relative_base),
        .stack_len = thread.stack.items.len,
        .last_result_base = thread.last_result_base,
        .last_result_count = thread.last_result_count,
        .last_error = undefined,
        .previous_error_handler = thread.error_handler,
    };
}

pub fn protectedCallContextWithErrors(comptime State: type, self: *State, thread: *Thread) ProtectedCallContext {
    var context = protectedCallContext(State, self, thread);
    context.last_error = self.last_error;
    return context;
}

pub fn runProtectedCall(comptime State: type, self: *State, thread: *Thread, context: ProtectedCallContext, callable: Value, args: []const Value) anyerror!ProtectedCallResult {
    try thread.ensureStack(self.allocator, context.absolute_base + 1 + args.len, self.callStackValueLimit(thread));
    thread.stack.items[context.absolute_base] = callable;
    for (args, 0..) |arg, index| thread.stack.items[context.absolute_base + 1 + index] = arg;

    thread.error_handler = context.error_handler;
    self.last_error = null;
    return runProtectedBody(State, self, thread, context, args.len) catch |err| {
        if (err != error.CoroutineYield) thread.error_handler = context.previous_error_handler;
        return err;
    };
}

fn runProtectedBody(comptime State: type, self: *State, thread: *Thread, context: ProtectedCallContext, arg_count: usize) anyerror!ProtectedCallResult {
    const callee = thread.stack.items[context.absolute_base];
    self.invokeValue(thread, .{ .base = context.relative_base, .arg_count = @intCast(arg_count), .return_count = bytecode.multret_count }, 0) catch |err| {
        return protectedCallFailure(State, self, thread, context, callee, err);
    };
    self.runThreadUntil(thread, context.frame_count) catch |err| {
        return protectedCallFailure(State, self, thread, context, callee, err);
    };

    const values = try self.allocator.alloc(Value, thread.last_result_count);
    errdefer self.allocator.free(values);
    for (values, 0..) |*value, index| value.* = thread.stack.items[thread.last_result_base + index];
    _ = try self.restoreProtectedCall(thread, context, .nil);
    return .{ .success = values };
}

fn protectedCallFailure(comptime State: type, self: *State, thread: *Thread, context: ProtectedCallContext, callee: Value, err: anyerror) anyerror!ProtectedCallResult {
    switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode, error.OutOfMemory => {
            if (thread.frames.items.len < context.frame_count) return err;
            self.noteCaughtError(err);
            if (!self.error_handled and thread.error_handler != .nil) {
                const mark_count = thread.native_mark_count;
                defer thread.native_mark_count = mark_count;
                if (callee != .closure) State.pushNativeMark(thread, context.frame_count, callee);
                try self.applyMessageHandler(thread);
            }
            const failure = try self.restoreProtectedCall(thread, context, self.currentErrorValue());
            return .{ .failure = failure };
        },
        else => return err,
    }
}

pub fn pushProtectedContinuation(comptime State: type, self: *State, thread: *Thread, context: ProtectedCallContext, base: u32, return_count: u16) !void {
    thread.continuation_order += 1;
    try thread.protected_continuations.append(self.allocator, .{
        .order = thread.continuation_order,
        .context = context,
        .base = base,
        .return_count = return_count,
    });
    thread.noteContinuation(context.frame_count);
}

pub fn readyProtectedContinuationIndex(thread: *Thread) ?usize {
    for (thread.protected_continuations.items, 0..) |continuation, index| {
        if (continuation.context.frame_count == thread.frames.items.len) return index;
    }
    return null;
}

pub fn errorProtectedContinuationIndex(thread: *Thread) ?usize {
    var best_index: ?usize = null;
    var best_frame_count: usize = 0;
    for (thread.protected_continuations.items, 0..) |continuation, index| {
        const frame_count = continuation.context.frame_count;
        if (frame_count > thread.frames.items.len) continue;
        if (best_index == null or frame_count > best_frame_count) {
            best_index = index;
            best_frame_count = frame_count;
        }
    }
    return best_index;
}

pub fn completeReadyProtectedContinuation(comptime State: type, self: *State, thread: *Thread) !bool {
    const index = readyProtectedContinuationIndex(thread) orelse return false;
    const continuation = thread.protected_continuations.items[index];
    const values = try self.copyStackSlice(thread, thread.last_result_base, thread.last_result_count);
    defer self.allocator.free(values);
    _ = try self.restoreProtectedCall(thread, continuation.context, .nil);
    _ = thread.protected_continuations.orderedRemove(index);
    thread.refreshContinuationFrameCount();
    try returnProtectedContinuationSuccess(State, self, thread, continuation, values);
    return true;
}

pub fn completeProtectedContinuationError(comptime State: type, self: *State, thread: *Thread) !bool {
    const index = errorProtectedContinuationIndex(thread) orelse return false;
    const continuation = thread.protected_continuations.items[index];
    // Drop pairs calls abandoned by this handler. A native protected __pairs
    // can share its frame depth with an outer pairs call, which must survive.
    var pairs_index = thread.pairs_continuations.items.len;
    while (pairs_index > 0) {
        pairs_index -= 1;
        const pending = thread.pairs_continuations.items[pairs_index];
        if (pending.frame_count == continuation.context.frame_count and pending.order < continuation.order) {
            _ = thread.pairs_continuations.orderedRemove(pairs_index);
        }
    }
    try self.applyMessageHandler(thread);
    const failure = try self.restoreProtectedCall(thread, continuation.context, self.currentErrorValue());
    for (thread.protected_continuations.items, 0..) |pending, pending_index| {
        if (pending.order != continuation.order) continue;
        _ = thread.protected_continuations.orderedRemove(pending_index);
        break;
    }
    thread.refreshContinuationFrameCount();
    try returnProtectedResult(State, self, thread, continuation.base, continuation.return_count, .{ .failure = failure });
    return true;
}

pub fn returnProtectedContinuationSuccess(comptime State: type, self: *State, thread: *Thread, continuation: ProtectedContinuation, values: []Value) !void {
    try returnProtectedResult(State, self, thread, continuation.base, continuation.return_count, .{ .success = values });
}

pub fn returnProtectedResult(comptime State: type, self: *State, thread: *Thread, base: u32, return_count: u16, result: ProtectedCallResult) !void {
    switch (result) {
        .success => |values| {
            var returns = std.ArrayList(Value).empty;
            defer returns.deinit(self.allocator);
            try returns.append(self.allocator, .{ .boolean = true });
            try returns.appendSlice(self.allocator, values);
            try self.returnValues(thread, base, return_count, returns.items);
        },
        .failure => |error_value| try self.returnValues(thread, base, return_count, &.{ .{ .boolean = false }, try self.caughtErrorValue(error_value) }),
    }
}

pub fn collectArgs(comptime State: type, self: *State, thread: *Thread, op: bytecode.Call, first: u32) ![]Value {
    if (op.arg_count <= first) return self.allocator.alloc(Value, 0);
    const args = try self.allocator.alloc(Value, op.arg_count - first);
    for (args, 0..) |*arg, index| arg.* = argValue(self, thread, op, first + @as(u32, @intCast(index)));
    return args;
}

pub fn resolveReturnCount(comptime State: type, self: *State, count: u16, available: usize) !usize {
    _ = self;
    return if (count == bytecode.multret_count) available else count;
}

pub fn prepareClosureFrame(comptime State: type, self: *State, thread: *Thread, closure: *Closure, source_base: usize, frame_base: usize, arg_count: usize, return_start: usize, return_count: u16) !CallFrame {
    const register_count = @max(closure.proto.max_registers, 1);
    const param_count = @as(usize, closure.proto.param_count);
    const copied = @min(arg_count, param_count);
    const varargs = try self.captureVarargs(thread, source_base + 1 + param_count, if (closure.proto.is_vararg and arg_count > param_count) arg_count - param_count else 0);
    errdefer if (varargs.len != 0) self.allocator.free(varargs);
    try thread.ensureStack(self.allocator, frame_base + register_count, self.callStackValueLimit(thread));

    if (frame_base != source_base + 1) {
        for (0..copied) |index| thread.stack.items[frame_base + index] = thread.stack.items[source_base + 1 + index];
    }
    for (copied..register_count) |index| thread.stack.items[frame_base + index] = .nil;

    const readonly_vararg = closure.proto.named_vararg_readonly;
    if (closure.proto.named_vararg and !readonly_vararg) {
        thread.stack.items[frame_base + param_count] = try self.namedVarargTable(varargs);
    }
    thread.frame_storage_bytes += varargs.len * @sizeOf(Value);

    return .{
        .closure = closure,
        .proto = closure.proto,
        .base = frame_base,
        .pc = 0,
        .return_start = return_start,
        .return_count = return_count,
        .varargs = varargs,
        .owns_varargs = varargs.len != 0,
        .named_vararg_readonly = readonly_vararg,
    };
}
