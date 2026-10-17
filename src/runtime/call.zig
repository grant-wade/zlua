const std = @import("std");
const compile = @import("../compile.zig");
const errors = @import("../errors.zig");
const stdlib = @import("../stdlib.zig");
const coroutine_mod = @import("coroutine.zig");
const debug_mod = @import("debug.zig");
const failure_mod = @import("failure.zig");
const index_mod = @import("index.zig");
const io_mod = @import("io.zig");
const load_mod = @import("load.zig");
const metatable_mod = @import("metatable.zig");
const operators_mod = @import("operators.zig");
const State = @import("state.zig").State;
const state_mod = @import("state.zig");
const types = @import("types.zig");
const upvalue_mod = @import("upvalue.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const bytecode = compile.bytecode;
const Value = types.Value;
const ProtectedCallResult = types.ProtectedCallResult;
const ProtectedCallContext = types.ProtectedCallContext;
const ProtectedContinuation = types.ProtectedContinuation;
const CallOneContinuationResult = types.CallOneContinuationResult;
const Closure = types.Closure;
const Thread = types.Thread;
const CallFrame = types.CallFrame;
const freeProtectedResult = value_mod.freeProtectedResult;
const argValue = value_mod.argValue;
const truthy = value_mod.truthy;
const lua_max_c_calls = state_mod.lua_max_c_calls;
const stack_error_frames = state_mod.stack_error_frames;
const stack_error_values = state_mod.stack_error_values;
const max_metamethod_depth = state_mod.max_metamethod_depth;
const NativeFn = types.NativeFn;
const valuesEqual = value_mod.valuesEqual;
const toInteger = value_mod.toInteger;
const nativeHookName = value_mod.nativeHookName;
const floatToInteger = value_mod.floatToInteger;
const arrayIndex = value_mod.arrayIndex;
const appendFmt = value_mod.appendFmt;
const isNativeCallable = value_mod.isNativeCallable;
const functionLike = value_mod.functionLike;
const Table = types.Table;

pub fn callOneResult(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!Value {
    return callOneResultMaybeContinuation(self, thread, callable, args, null);
}

fn callOneResultWithContinuation(self: *State, thread: *Thread, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value {
    return callOneResultMaybeContinuation(self, thread, callable, args, result);
}

pub fn callOneMetamethodWithContinuation(self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value, result: CallOneContinuationResult) anyerror!Value {
    const previous_name = thread.next_call_name;
    const previous_namewhat = thread.next_call_namewhat;
    thread.next_call_name = metamethodDebugName(name);
    thread.next_call_namewhat = "metamethod";
    defer {
        thread.next_call_name = previous_name;
        thread.next_call_namewhat = previous_namewhat;
    }
    return callOneResultWithContinuation(self, thread, callable, args, result);
}

pub fn callOneMetamethod(self: *State, thread: *Thread, name: []const u8, callable: Value, args: []const Value) anyerror!Value {
    return callOneNamed(self, thread, metamethodDebugName(name), "metamethod", callable, args);
}

/// Calls `callable` for one result; a Lua callee reports `namewhat 'name'`.
pub fn callOneNamed(self: *State, thread: *Thread, name: []const u8, namewhat: []const u8, callable: Value, args: []const Value) anyerror!Value {
    const previous_name = thread.next_call_name;
    const previous_namewhat = thread.next_call_namewhat;
    thread.next_call_name = name;
    thread.next_call_namewhat = namewhat;
    defer {
        thread.next_call_name = previous_name;
        thread.next_call_namewhat = previous_namewhat;
    }
    return callOneResult(self, thread, callable, args);
}

fn metamethodDebugName(name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, name, "__")) name[2..] else name;
}

fn callOneResultMaybeContinuation(self: *State, thread: *Thread, callable: Value, args: []const Value, continuation_result: ?CallOneContinuationResult) anyerror!Value {
    const frame_count = thread.frames.items.len;
    const relative_base = thread.scratchRegister();
    const base = thread.frames.items[frame_count - 1].base + @as(usize, relative_base);
    try thread.ensureStack(self.allocator, base + 1 + args.len, callStackValueLimit(self, thread));
    thread.stack.items[base] = callable;
    for (args, 0..) |arg, index| thread.stack.items[base + 1 + index] = arg;

    invokeValue(self, thread, .{ .base = relative_base, .arg_count = @intCast(args.len), .return_count = 1 }, 0) catch |err| switch (err) {
        error.CoroutineYield => {
            if (continuation_result) |result| try pushCallOneContinuation(self, thread, frame_count, result);
            return err;
        },
        else => return err,
    };
    vm_mod.runThreadUntil(self, thread, frame_count) catch |err| switch (err) {
        error.CoroutineYield => {
            if (continuation_result) |result| try pushCallOneContinuation(self, thread, frame_count, result);
            return err;
        },
        else => return err,
    };
    return thread.stack.items[base];
}

fn pushCallOneContinuation(self: *State, thread: *Thread, frame_count: usize, result: CallOneContinuationResult) !void {
    try thread.call_one_continuations.append(self.allocator, .{ .frame_count = frame_count, .result = result });
    thread.noteContinuation(frame_count);
}

fn readyCallOneContinuationIndex(thread: *Thread) ?usize {
    for (thread.call_one_continuations.items, 0..) |continuation, index| {
        if (continuation.frame_count == thread.frames.items.len) return index;
    }
    return null;
}

pub fn completeReadyCallOneContinuation(self: *State, thread: *Thread) !bool {
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
            try operators_mod.jumpIfBranchResult(self, thread, truthy(value), branch.jump_if_truthy, branch.offset);
        },
        .branch_inverted_truthy => |branch| {
            thread.last_result_count = 0;
            thread.last_transfer_count = 0;
            try operators_mod.jumpIfBranchResult(self, thread, !truthy(value), branch.jump_if_truthy, branch.offset);
        },
        .concat => |pending| {
            thread.stack.items[pending.first + pending.count - 1] = value;
            try operators_mod.finishConcatRange(self, thread, pending.dest, pending.first, pending.count);
        },
        .discard => {},
    }
    return true;
}

pub fn protectedCall(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror!ProtectedCallResult {
    const context = protectedCallContextWithErrors(self, thread);
    return runProtectedCall(self, thread, context, callable, args);
}

fn protectedCallContext(_: *State, thread: *Thread) ProtectedCallContext {
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

pub fn protectedCallContextWithErrors(self: *State, thread: *Thread) ProtectedCallContext {
    var context = protectedCallContext(self, thread);
    context.last_error = self.last_error;
    return context;
}

pub fn runProtectedCall(self: *State, thread: *Thread, context: ProtectedCallContext, callable: Value, args: []const Value) anyerror!ProtectedCallResult {
    try thread.ensureStack(self.allocator, context.absolute_base + 1 + args.len, callStackValueLimit(self, thread));
    thread.stack.items[context.absolute_base] = callable;
    for (args, 0..) |arg, index| thread.stack.items[context.absolute_base + 1 + index] = arg;

    thread.error_handler = context.error_handler;
    self.last_error = null;
    return runProtectedBody(self, thread, context, args.len) catch |err| {
        if (err != error.CoroutineYield) thread.error_handler = context.previous_error_handler;
        return err;
    };
}

fn runProtectedBody(self: *State, thread: *Thread, context: ProtectedCallContext, arg_count: usize) anyerror!ProtectedCallResult {
    const callee = thread.stack.items[context.absolute_base];
    invokeValue(self, thread, .{ .base = context.relative_base, .arg_count = @intCast(arg_count), .return_count = bytecode.multret_count }, 0) catch |err| {
        return protectedCallFailure(self, thread, context, callee, err);
    };
    vm_mod.runThreadUntil(self, thread, context.frame_count) catch |err| {
        return protectedCallFailure(self, thread, context, callee, err);
    };

    const values = try self.allocator.alloc(Value, thread.last_result_count);
    errdefer self.allocator.free(values);
    for (values, 0..) |*value, index| value.* = thread.stack.items[thread.last_result_base + index];
    _ = try restoreProtectedCall(self, thread, context, .nil);
    return .{ .success = values };
}

fn protectedCallFailure(self: *State, thread: *Thread, context: ProtectedCallContext, callee: Value, err: anyerror) anyerror!ProtectedCallResult {
    switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode, error.OutOfMemory => {
            if (thread.frames.items.len < context.frame_count) return err;
            noteCaughtError(self, err);
            if (!self.error_handled and thread.error_handler != .nil) {
                const mark_count = thread.native_mark_count;
                defer thread.native_mark_count = mark_count;
                if (callee != .closure) pushNativeMark(thread, context.frame_count, callee);
                try applyMessageHandler(self, thread);
            }
            const failure = try restoreProtectedCall(self, thread, context, self.currentErrorValue());
            return .{ .failure = failure };
        },
        else => return err,
    }
}

fn pushProtectedContinuation(self: *State, thread: *Thread, context: ProtectedCallContext, base: u32, return_count: u16) !void {
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

fn errorProtectedContinuationIndex(thread: *Thread) ?usize {
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

pub fn completeReadyProtectedContinuation(self: *State, thread: *Thread) !bool {
    const index = readyProtectedContinuationIndex(thread) orelse return false;
    const continuation = thread.protected_continuations.items[index];
    const values = try coroutine_mod.copyStackSlice(self, thread, thread.last_result_base, thread.last_result_count);
    defer self.allocator.free(values);
    _ = try restoreProtectedCall(self, thread, continuation.context, .nil);
    _ = thread.protected_continuations.orderedRemove(index);
    thread.refreshContinuationFrameCount();
    try returnProtectedContinuationSuccess(self, thread, continuation, values);
    return true;
}

pub fn completeProtectedContinuationError(self: *State, thread: *Thread) !bool {
    const index = errorProtectedContinuationIndex(thread) orelse return false;
    const continuation = thread.protected_continuations.items[index];
    // A native protected __pairs can share its frame depth with an outer pairs call, which must survive.
    var pairs_index = thread.pairs_continuations.items.len;
    while (pairs_index > 0) {
        pairs_index -= 1;
        const pending = thread.pairs_continuations.items[pairs_index];
        if (pending.frame_count == continuation.context.frame_count and pending.order < continuation.order) {
            _ = thread.pairs_continuations.orderedRemove(pairs_index);
        }
    }
    try applyMessageHandler(self, thread);
    const failure = try restoreProtectedCall(self, thread, continuation.context, self.currentErrorValue());
    for (thread.protected_continuations.items, 0..) |pending, pending_index| {
        if (pending.order != continuation.order) continue;
        _ = thread.protected_continuations.orderedRemove(pending_index);
        break;
    }
    thread.refreshContinuationFrameCount();
    try returnProtectedResult(self, thread, continuation.base, continuation.return_count, .{ .failure = failure });
    return true;
}

fn returnProtectedContinuationSuccess(self: *State, thread: *Thread, continuation: ProtectedContinuation, values: []Value) !void {
    try returnProtectedResult(self, thread, continuation.base, continuation.return_count, .{ .success = values });
}

fn returnProtectedResult(self: *State, thread: *Thread, base: u32, return_count: u16, result: ProtectedCallResult) !void {
    switch (result) {
        .success => |values| {
            var returns = std.ArrayList(Value).empty;
            defer returns.deinit(self.allocator);
            try returns.append(self.allocator, .{ .boolean = true });
            try returns.appendSlice(self.allocator, values);
            try self.returnValues(thread, base, return_count, returns.items);
        },
        .failure => |error_value| try self.returnValues(thread, base, return_count, &.{ .{ .boolean = false }, try caughtErrorValue(self, error_value) }),
    }
}

pub fn collectArgs(self: *State, thread: *Thread, op: bytecode.Call, first: u32) ![]Value {
    if (op.arg_count <= first) return self.allocator.alloc(Value, 0);
    const args = try self.allocator.alloc(Value, op.arg_count - first);
    for (args, 0..) |*arg, index| arg.* = argValue(self, thread, op, first + @as(u32, @intCast(index)));
    return args;
}

pub fn resolveReturnCount(self: *State, count: u16, available: usize) !usize {
    _ = self;
    return if (count == bytecode.multret_count) available else count;
}

pub fn prepareClosureFrame(self: *State, thread: *Thread, closure: *Closure, source_base: usize, frame_base: usize, arg_count: usize, return_start: usize, return_count: u16) !CallFrame {
    const register_count = @max(closure.proto.max_registers, 1);
    const param_count = @as(usize, closure.proto.param_count);
    const copied = @min(arg_count, param_count);
    const varargs = try captureVarargs(self, thread, source_base + 1 + param_count, if (closure.proto.is_vararg and arg_count > param_count) arg_count - param_count else 0);
    errdefer if (varargs.len != 0) self.allocator.free(varargs);
    try thread.ensureStack(self.allocator, frame_base + register_count, callStackValueLimit(self, thread));

    if (frame_base != source_base + 1) {
        for (0..copied) |index| thread.stack.items[frame_base + index] = thread.stack.items[source_base + 1 + index];
    }
    for (copied..register_count) |index| thread.stack.items[frame_base + index] = .nil;

    const readonly_vararg = closure.proto.named_vararg_readonly;
    if (closure.proto.named_vararg and !readonly_vararg) {
        thread.stack.items[frame_base + param_count] = try namedVarargTable(self, varargs);
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
            error_value = try cStackOverflowValue(self, thread);
            native_calls += 1;
            continue;
        }
        if (c_calls >= lua_max_c_calls / 10 * 11) {
            error_value = .{ .string = try self.intern("error in error handling") };
            break;
        }
        if (handler != .closure) native_calls += 1;
        const frame_count = thread.frames.items.len;
        if (try callMessageHandler(self, thread, handler, error_value)) |result| {
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
    const context = protectedCallContext(self, thread);
    thread.ensureStack(self.allocator, context.absolute_base + 2, self.stackValueLimit() + stack_error_values) catch |err| switch (err) {
        error.StackOverflow => return errorInErrorHandling(self),
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
    invokeValue(self, thread, .{ .base = context.relative_base, .arg_count = 1, .return_count = bytecode.multret_count }, 0) catch |err| return messageHandlerFailure(self, err);
    vm_mod.runThreadUntil(self, thread, context.frame_count) catch |err| return messageHandlerFailure(self, err);
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
    const site = failure_mod.instructionErrorSite(self, thread) orelse return .{ .string = try self.intern(message) };
    var out = std.ArrayList(u8).empty;
    defer out.deinit(self.allocator);
    try appendFmt(self.allocator, &out, "{s}:{d}: {s}", .{ load_mod.runtimeSourceName(frame.proto.source_name), site.line, message });
    return .{ .string = try self.intern(out.items) };
}

/// Records a native function without a calling instruction for tracebacks.
fn pushNativeMark(thread: *Thread, frame_count: usize, callee: Value) void {
    if (thread.native_mark_count == thread.native_marks.len) return;
    thread.native_marks[thread.native_mark_count] = .{ .frame_count = @intCast(frame_count), .callee = callee };
    thread.native_mark_count += 1;
}

fn messageHandlerFailure(self: *State, err: anyerror) !?Value {
    switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode, error.OutOfMemory => {
            noteCaughtError(self, err);
            return null;
        },
        else => return err,
    }
}

pub fn checkCStack(self: *State, thread: *Thread) !void {
    if (self.execution_depth >= lua_max_c_calls / 10 * 11) {
        _ = try errorInErrorHandling(self);
        return error.RuntimeError;
    }
    if (self.execution_depth != lua_max_c_calls) return;
    const frame_count = thread.frames.items.len;
    if (frame_count > 1) thread.frames.items.len = frame_count - 1;
    const value = cStackOverflowValue(self, thread);
    thread.frames.items.len = frame_count;
    return self.failValue(try value);
}

fn errorInErrorHandling(self: *State) !?Value {
    self.last_error = .{ .lua_value = .{ .string = try self.intern("error in error handling") } };
    self.error_handled = true;
    return null;
}

pub fn callCollect(self: *State, thread: *Thread, callable: Value, args: []const Value) anyerror![]Value {
    const frame_count = thread.frames.items.len;
    const relative_base = thread.scratchRegister();
    const base = thread.frames.items[frame_count - 1].base + @as(usize, relative_base);
    try thread.ensureStack(self.allocator, base + 1 + args.len, callStackValueLimit(self, thread));
    thread.stack.items[base] = callable;
    for (args, 0..) |arg, index| thread.stack.items[base + 1 + index] = arg;

    try invokeValue(self, thread, .{ .base = relative_base, .arg_count = @intCast(args.len), .return_count = bytecode.multret_count }, 0);
    try vm_mod.runThreadUntil(self, thread, frame_count);
    return coroutine_mod.copyStackSlice(self, thread, thread.last_result_base, thread.last_result_count);
}

pub fn callValue(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const resolved = try resolveCall(self, thread, op);
    const callee = vm_mod.get(self, thread, resolved.base);
    if (callee == .closure) {
        const call_name = thread.next_call_name;
        const call_namewhat = thread.next_call_namewhat;
        thread.next_call_name = null;
        thread.next_call_namewhat = null;
        try callClosure(self, thread, resolved, callee.closure, call_name, call_namewhat);
        return;
    }
    try invokeValue(self, thread, resolved, 0);
}

/// Native code the runtime runs on top of the current frame, such as error handling.
pub fn runtimeNativeCall(thread: *Thread) types.NativeCall {
    return .{ .base = thread.scratchRegister(), .arg_count = 0, .frame_count = thread.frames.items.len, .from_native = false };
}

pub fn nativeCallInfo(thread: *Thread, resolved: bytecode.Call, outer: ?types.NativeCall, name: ?[]const u8, namewhat: ?[]const u8, extra_args: usize) types.NativeCall {
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
    const callee = vm_mod.get(self, thread, resolved.base);
    if (callee == .coroutine_wrapper) {
        const previous_native_call = thread.native_call;
        defer thread.native_call = previous_native_call;
        thread.native_call = nativeCallInfo(thread, resolved, previous_native_call, null, null, depth);
        try coroutine_mod.callCoroutineWrapper(self, thread, resolved, callee.coroutine_wrapper);
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
        try debug_mod.callHook(self, thread, "call");
    }
    switch (callee) {
        .closure => |closure| try callClosure(self, thread, resolved, closure, call_name, call_namewhat),
        .api_callback => |id| try self.callApiCallbackDispatch(thread, resolved, id),
        .native_print => {
            for (0..resolved.arg_count) |index| {
                if (index != 0) try io_mod.writeStdout(self, "\t");
                const text = try metatable_mod.valueToString(self, thread, argValue(self, thread, resolved, @intCast(index)));
                try io_mod.writeStdout(self, text);
            }
            try io_mod.writeStdout(self, "\n");
            try io_mod.flushStdoutAfterPrint(self);
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{});
        },
        .native_tostring => {
            if (resolved.arg_count == 0) return self.failArgumentMessage("tostring", 1, "value expected");
            const value = vm_mod.get(self, thread, resolved.base + 1);
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{.{ .string = try metatable_mod.valueToString(self, thread, value) }});
        },
        .native_getmetatable => {
            if (resolved.arg_count == 0) return self.failArgumentMessage("getmetatable", 1, "value expected");
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{try metatable_mod.getMetatableValue(self, argValue(self, thread, resolved, 0))});
        },
        .native_setmetatable => {
            const table_value = argValue(self, thread, resolved, 0);
            if (table_value != .table) return self.failArgumentType("setmetatable", 1, "table", table_value);
            const metatable_value = argValue(self, thread, resolved, 1);
            if (metatable_value != .nil and metatable_value != .table) return self.failArgumentType("setmetatable", 2, "nil or table", metatable_value);
            try metatable_mod.setMetatableValue(self, table_value, argValue(self, thread, resolved, 1));
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{table_value});
        },
        .native_rawequal => {
            if (resolved.arg_count < 2) return self.failArgumentMessage("rawequal", resolved.arg_count + 1, "value expected");
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{.{ .boolean = valuesEqual(argValue(self, thread, resolved, 0), argValue(self, thread, resolved, 1)) }});
        },
        .native_rawget => {
            _ = try self.expectArgumentTable(thread, resolved, "rawget", 0);
            if (resolved.arg_count < 2) return self.failArgumentMessage("rawget", 2, "value expected");
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{try index_mod.rawGet(self, argValue(self, thread, resolved, 0), argValue(self, thread, resolved, 1))});
        },
        .native_rawset => {
            const table = argValue(self, thread, resolved, 0);
            _ = try self.expectArgumentTable(thread, resolved, "rawset", 0);
            if (resolved.arg_count < 3) return self.failArgumentMessage("rawset", @max(resolved.arg_count + 1, 2), "value expected");
            try index_mod.rawSet(self, table, argValue(self, thread, resolved, 1), argValue(self, thread, resolved, 2));
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{table});
        },
        .native_rawlen => {
            const value = argValue(self, thread, resolved, 0);
            if (value != .string and value != .table) return self.failArgumentType("rawlen", 1, "table or string", value);
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{try index_mod.rawLen(self, value)});
        },
        .native_next => {
            _ = try self.expectArgumentTable(thread, resolved, "next", 0);
            const values = try index_mod.nextValues(self, argValue(self, thread, resolved, 0), argValue(self, thread, resolved, 1));
            const count: usize = if (values[0] == .nil) 1 else 2;
            try self.returnValues(thread, resolved.base, resolved.return_count, values[0..count]);
        },
        .native_pairs => {
            if (resolved.arg_count == 0) return self.failArgumentMessage("pairs", 1, "value expected");
            const value = argValue(self, thread, resolved, 0);
            if (try metatable_mod.getMetaEvent(self, value, .__pairs)) |metamethod| {
                thread.native_call_depth -= 1;
                defer thread.native_call_depth += 1;
                try index_mod.callPairsMetamethod(self, thread, resolved, metamethod, value);
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
            const values = try index_mod.ipairsIterValues(self, thread, argValue(self, thread, resolved, 0), argValue(self, thread, resolved, 1));
            try self.returnValues(thread, resolved.base, resolved.return_count, values[0..if (values[0] == .nil) @as(usize, 1) else 2]);
        },
        .native_table_create => {
            const array_hint, const hash_hint = try tableCreateHints(self, thread, resolved);
            if (hash_hint > 1 << 30) return self.fail("table overflow");
            try self.returnValues(thread, resolved.base, resolved.return_count, &.{try self.newTableWithHints(array_hint, hash_hint)});
        },
        .native_select => try selectValues(self, thread, resolved),
        .native_assert => try assertValues(self, thread, resolved),
        .native_error => try errorValue(self, thread, resolved),
        .native_pcall => try pcallValues(self, thread, resolved),
        .native_xpcall => try xpcallValues(self, thread, resolved),
        .native_collectgarbage => try self.gc.collectGarbageValue(thread, resolved),
        .native_debug_traceback => try debug_mod.tracebackValue(self, thread, resolved),
        .native_coroutine_create => try coroutine_mod.coroutineCreate(self, thread, resolved),
        .native_coroutine_resume => try coroutine_mod.coroutineResume(self, thread, resolved),
        .native_coroutine_yield => try coroutine_mod.coroutineYield(self, thread, resolved),
        .native_coroutine_status => try coroutine_mod.coroutineStatus(self, thread, resolved),
        .native_coroutine_running => try coroutine_mod.coroutineRunning(self, thread, resolved),
        .native_coroutine_isyieldable => try coroutine_mod.coroutineIsYieldable(self, thread, resolved),
        .native_coroutine_close => try coroutine_mod.coroutineClose(self, thread, resolved),
        .native_coroutine_wrap => try coroutine_mod.coroutineWrap(self, thread, resolved),
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
        .native => |native| try callNative(self, native, thread, resolved),
        else => {
            const metamethod = try metatable_mod.getMetaEvent(self, callee, .__call) orelse return failure_mod.failCallTypeError(self, thread, callee, call_name, call_namewhat);
            try prependCallArgument(self, thread, resolved, metamethod, callee);
            thread.next_call_name = call_name;
            thread.next_call_namewhat = call_namewhat;
            try invokeValue(self, thread, .{ .base = resolved.base, .arg_count = resolved.arg_count + 1, .return_count = resolved.return_count }, depth + 1);
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
        try debug_mod.callReturnHook(self, thread, call_name orelse nativeHookName(callee));
    }
}

fn prependCallArgument(self: *State, thread: *Thread, resolved: bytecode.Call, metamethod: Value, receiver: Value) !void {
    const frame = thread.frames.items[thread.frames.items.len - 1];
    const base = frame.base + resolved.base;
    try thread.ensureStack(self.allocator, base + 2 + resolved.arg_count, callStackValueLimit(self, thread));
    var index: usize = resolved.arg_count;
    while (index > 0) {
        index -= 1;
        thread.stack.items[base + 2 + index] = thread.stack.items[base + 1 + index];
    }
    thread.stack.items[base] = metamethod;
    thread.stack.items[base + 1] = receiver;
}

fn restoreProtectedCall(
    self: *State,
    thread: *Thread,
    context: ProtectedCallContext,
    error_value: Value,
) !Value {
    var failure = error_value;
    thread.protected_close_depth += 1;
    defer thread.protected_close_depth -= 1;
    upvalue_mod.closeFramesTo(self, thread, context.frame_count, error_value) catch |err| switch (err) {
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

fn checkStackValueOverflow(self: *State, thread: *Thread, needed: usize) !void {
    if (!thread.stack_error_space) {
        thread.stack_error_space = true;
        return failure_mod.failRuntimeDetail(self, thread, "stack overflow");
    }
    if (needed <= self.stackValueLimit() + stack_error_values) return;
    _ = try errorInErrorHandling(self);
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
        return failure_mod.failRuntimeDetail(self, thread, "stack overflow");
    }
    if (thread.frames.items.len < self.callFrameLimit() + stack_error_frames) return;
    _ = try errorInErrorHandling(self);
    return error.RuntimeError;
}

fn callClosure(self: *State, thread: *Thread, op: bytecode.Call, closure: *Closure, debug_name_override: ?[]const u8, debug_namewhat_override: ?[]const u8) !void {
    if (thread.frames.items.len >= self.callFrameLimit()) try checkFrameOverflow(self, thread);

    const caller = thread.frames.items[thread.frames.items.len - 1];
    const base = caller.base + op.base;
    if (base + 1 + @max(closure.proto.max_registers, 1) > self.stackValueLimit()) try checkStackValueOverflow(self, thread, base + 1 + @max(closure.proto.max_registers, 1));
    var frame = try prepareClosureFrame(self, thread, closure, base, base + 1, @intCast(op.arg_count), base, op.return_count);
    frame.debug_name_override = debug_name_override;
    frame.debug_namewhat_override = debug_namewhat_override;
    errdefer thread.releaseFrame(&frame, self.allocator);
    try thread.frames.append(self.allocator, frame);
    if (thread.hook_call and !thread.hook_running) try debug_mod.callHook(self, thread, "call");
}

pub fn tailCallValue(self: *State, thread: *Thread, op: bytecode.Call) anyerror!void {
    var resolved = try resolveCall(self, thread, op);
    var depth: usize = 0;
    while (true) {
        const callee = vm_mod.get(self, thread, resolved.base);
        switch (callee) {
            .closure => break,
            .coroutine_wrapper => break,
            else => if (isNativeCallable(callee)) break,
        }

        if (depth > max_metamethod_depth) return self.fail("'__call' chain too long");
        const metamethod = try metatable_mod.getMetaEvent(self, callee, .__call) orelse break;
        try prependCallArgument(self, thread, resolved, metamethod, callee);
        resolved.arg_count += 1;
        depth += 1;
    }

    const callee = vm_mod.get(self, thread, resolved.base);
    switch (callee) {
        .closure => |closure| {
            try upvalue_mod.closeActiveToBeClosedInTopFrame(self, thread, null);
            const frame = thread.frames.items[thread.frames.items.len - 1];
            upvalue_mod.closeUpvalues(self, thread, frame.base);
            const new_frame = try prepareClosureFrame(self, thread, closure, frame.base + resolved.base, frame.base, @intCast(resolved.arg_count), frame.return_start, frame.return_count);
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
                try debug_mod.callHook(self, thread, "tail call");
            }
        },
        else => {
            const frame = thread.frames.items[thread.frames.items.len - 1];
            const frame_count = thread.frames.items.len;
            invokeValue(self, thread, .{ .base = resolved.base, .arg_count = resolved.arg_count, .return_count = frame.return_count }, depth) catch |err| switch (err) {
                error.CoroutineYield => {
                    try pushTailCallContinuation(self, thread, frame_count, resolved.base, frame.return_count);
                    return err;
                },
                else => return err,
            };
            try vm_mod.runThreadUntil(self, thread, frame_count);
            try returnFromFrame(self, thread, resolved.base, frame.return_count);
        },
    }
}

pub fn returnFromFrame(self: *State, thread: *Thread, first: u32, count: u16) !void {
    const frame_index = thread.frames.items.len - 1;
    var frame = &thread.frames.items[frame_index];
    if (frame.pending_returns == null and !frame.proto.has_to_close_locals and (!thread.hook_return or thread.hook_running)) {
        const source_start = frame.base + first;
        const source_count = try resolveResultCount(self, thread, source_start, count);
        upvalue_mod.closeUpvalues(self, thread, frame.base);
        if (thread.frames.items.len == 1) {
            thread.last_result_base = source_start;
            thread.last_result_count = source_count;
            thread.releaseFrame(frame, self.allocator);
            thread.frames.items.len = 0;
            return;
        }

        const return_start = frame.return_start;
        const return_count = try resolveReturnCount(self, frame.return_count, source_count);
        thread.releaseFrame(frame, self.allocator);
        thread.frames.items.len -= 1;

        try thread.ensureStack(self.allocator, return_start + return_count, callStackValueLimit(self, thread));
        const copied = @min(return_count, source_count);
        for (0..copied) |index| thread.stack.items[return_start + index] = thread.stack.items[source_start + index];
        for (copied..return_count) |index| thread.stack.items[return_start + index] = .nil;
        thread.last_result_base = return_start;
        thread.last_result_count = return_count;
        return;
    }

    const preserved = frame.pending_returns orelse blk: {
        const source_start = frame.base + first;
        const source_count = try resolveResultCount(self, thread, source_start, count);
        const values = try self.allocator.alloc(Value, source_count);
        for (values, 0..) |*value, index| value.* = thread.stack.items[source_start + index];
        frame.pending_returns = values;
        thread.frame_storage_bytes += values.len * @sizeOf(Value);
        break :blk values;
    };
    try upvalue_mod.closeActiveToBeClosedInTopFrame(self, thread, null);
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
        try debug_mod.callReturnHook(self, thread, frame.debug_name_override orelse frame.proto.debug_name);
    }
    frame = &thread.frames.items[frame_index];
    frame.pending_returns = null;
    thread.frame_storage_bytes -= preserved.len * @sizeOf(Value);
    defer self.allocator.free(preserved);
    upvalue_mod.closeUpvalues(self, thread, frame.base);
    if (thread.frames.items.len == 1) {
        const result_start = frame.base + first;
        try thread.ensureStack(self.allocator, result_start + preserved.len, callStackValueLimit(self, thread));
        for (preserved, 0..) |value, index| thread.stack.items[result_start + index] = value;
        thread.last_result_base = result_start;
        thread.last_result_count = preserved.len;
        thread.releaseFrame(frame, self.allocator);
        thread.frames.items.len = 0;
        return;
    }

    const return_start = frame.return_start;
    const return_count = try resolveReturnCount(self, frame.return_count, preserved.len);
    thread.releaseFrame(frame, self.allocator);
    thread.frames.items.len -= 1;

    try thread.ensureStack(self.allocator, return_start + return_count, callStackValueLimit(self, thread));
    const copied = @min(return_count, preserved.len);
    for (preserved[0..copied], 0..) |value, index| thread.stack.items[return_start + index] = value;
    for (copied..return_count) |index| thread.stack.items[return_start + index] = .nil;
    thread.last_result_base = return_start;
    thread.last_result_count = return_count;
}

fn captureVarargs(self: *State, thread: *Thread, source_start: usize, count: usize) ![]const Value {
    if (count == 0) return &.{};
    const values = try self.allocator.alloc(Value, count);
    for (0..count) |index| values[index] = thread.stack.items[source_start + index];
    return values;
}

fn namedVarargTable(self: *State, varargs: []const Value) !Value {
    const table_value = try self.newTableWithHints(@intCast(varargs.len), 1);
    const table = table_value.table;
    try self.setTableRaw(table, .{ .string = try self.intern("n") }, .{ .integer = @intCast(varargs.len) });
    for (varargs, 0..) |value, index| {
        try self.setTableRaw(table, .{ .integer = @intCast(index + 1) }, value);
    }
    return table_value;
}

pub fn namedVarargRead(varargs: []const Value, key: Value) Value {
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

pub fn resolveResultCount(self: *State, thread: *Thread, source_start: usize, count: u16) !usize {
    if (count != bytecode.multret_count) return count;
    if (thread.last_result_base < source_start) return self.fail("invalid multiple-return result state");
    const end = thread.last_result_base + thread.last_result_count;
    return if (end <= source_start) 0 else end - source_start;
}

pub fn loadVarargs(self: *State, thread: *Thread, op: bytecode.Vararg) !void {
    const frame = thread.frames.items[thread.frames.items.len - 1];
    if (frame.proto.named_vararg and !frame.named_vararg_readonly) return loadNamedVarargs(self, thread, frame, op);
    const actual_count = try resolveReturnCount(self, op.count, frame.varargs.len);
    const dest = frame.base + op.dest;
    try thread.ensureStack(self.allocator, dest + actual_count, callStackValueLimit(self, thread));
    const copied = @min(actual_count, frame.varargs.len);
    for (0..copied) |index| thread.stack.items[dest + index] = frame.varargs[index];
    for (copied..actual_count) |index| thread.stack.items[dest + index] = .nil;
    thread.last_result_base = dest;
    thread.last_result_count = actual_count;
}

fn loadNamedVarargs(self: *State, thread: *Thread, frame: CallFrame, op: bytecode.Vararg) !void {
    const table_value = thread.stack.items[frame.base + frame.proto.param_count];
    const table = try self.expectTable(table_value);
    const count = try namedVarargCount(self, table);
    const actual_count = try resolveReturnCount(self, op.count, count);
    const dest = frame.base + op.dest;
    try thread.ensureStack(self.allocator, dest + actual_count, callStackValueLimit(self, thread));
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
        if (message == .string) return failure_mod.throwStringWithLocation(self, thread, message.string, 1);
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
    return failure_mod.throwStringWithLocation(self, thread, value.string, level_index);
}

/// Like `luaG_errormsg` without a handler: nil becomes `<no error object>`.
pub fn caughtErrorValue(self: *State, value: Value) !Value {
    if (value == .nil) return .{ .string = try self.intern("<no error object>") };
    return value;
}

fn pcallValues(self: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0) return self.failArgumentMessage("pcall", 1, "value expected");
    const args = try collectArgs(self, thread, op, 1);
    defer self.allocator.free(args);
    try protectedCallValues(self, thread, op, argValue(self, thread, op, 0), args, .nil);
}

fn xpcallValues(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const handler = argValue(self, thread, op, 1);
    if (!functionLike(handler)) return self.failArgumentType("xpcall", 2, "function", handler);
    const args = try collectArgs(self, thread, op, 2);
    defer self.allocator.free(args);
    try protectedCallValues(self, thread, op, argValue(self, thread, op, 0), args, handler);
}

fn protectedCallValues(self: *State, thread: *Thread, op: bytecode.Call, callable: Value, args: []const Value, handler: Value) !void {
    var context = protectedCallContextWithErrors(self, thread);
    context.error_handler = handler;
    const result = runProtectedCall(self, thread, context, callable, args) catch |err| switch (err) {
        error.CoroutineYield => {
            try pushProtectedContinuation(self, thread, context, op.base, op.return_count);
            return err;
        },
        else => return err,
    };
    defer freeProtectedResult(self.allocator, result);
    try returnProtectedResult(self, thread, op.base, op.return_count, result);
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

pub fn completeReadyTailCallContinuation(self: *State, thread: *Thread) !bool {
    const index = readyTailCallContinuationIndex(thread) orelse return false;
    const continuation = thread.tail_call_continuations.orderedRemove(index);
    thread.refreshContinuationFrameCount();
    try returnFromFrame(self, thread, continuation.base, continuation.return_count);
    return true;
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

pub fn callNative(self: *State, native: NativeFn, thread: *Thread, op: bytecode.Call) !void {
    try stdlib.callNative(self, native, thread, op);
}

fn isYieldBlockingNative(value: Value) bool {
    return switch (value) {
        .native_pcall, .native_xpcall => false,
        .native => |native| native != .dofile,
        else => isNativeCallable(value),
    };
}

pub fn isRuntimeError(err: anyerror) bool {
    return switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => true,
        else => false,
    };
}

pub inline fn hasPendingContinuations(thread: *const Thread) bool {
    return (thread.pairs_continuations.items.len |
        thread.call_one_continuations.items.len |
        thread.protected_continuations.items.len |
        thread.tail_call_continuations.items.len |
        thread.generic_for_continuations.items.len) != 0;
}
