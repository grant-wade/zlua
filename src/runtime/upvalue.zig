const std = @import("std");
const compile = @import("../compile.zig");
const call_mod = @import("call.zig");
const failure_mod = @import("failure.zig");
const metatable_mod = @import("metatable.zig");
const rollback_mod = @import("rollback.zig");
const state_mod = @import("state.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const State = state_mod.State;
const bytecode = compile.bytecode;
const Value = types.Value;
const localActiveAt = value_mod.localActiveAt;
const Upvalue = types.Upvalue;
const Thread = types.Thread;

pub fn captureUpvalue(self: *State, thread: *Thread, stack_index: usize) !*Upvalue {
    var previous: ?*Upvalue = null;
    var current = thread.open_upvalues;
    while (current) |upvalue| : (current = upvalue.next) {
        if (upvalue.cell.open.stack_index <= stack_index) {
            if (upvalue.cell.open.stack_index == stack_index) return upvalue;
            break;
        }
        previous = upvalue;
    }

    const upvalue = try self.allocator.create(Upvalue);
    errdefer self.allocator.destroy(upvalue);
    upvalue.* = .{ .cell = .{ .open = .{ .owner = thread, .stack_index = stack_index } }, .next = current };
    try self.registerAllocation("upvalue_allocations", upvalue);
    self.gc.noteAllocation(@sizeOf(Upvalue));
    if (previous) |prev| {
        rollback_mod.touch(prev);
        prev.next = upvalue;
    } else {
        thread.open_upvalues = upvalue;
    }
    return upvalue;
}

pub fn readUpvalue(self: *State, thread: *Thread, index: bytecode.UpvalueIndex) Value {
    _ = self;
    const frame = thread.frames.items[thread.frames.items.len - 1];
    return frame.closure.upvalues()[index].get();
}

pub fn writeUpvalue(self: *State, thread: *Thread, index: bytecode.UpvalueIndex, value: Value) !void {
    const frame = thread.frames.items[thread.frames.items.len - 1];
    const upvalue = frame.closure.upvalues()[index];
    rollback_mod.touch(upvalue);
    switch (upvalue.cell) {
        .open => |slot| {
            try rollback_mod.threadWritable(slot.owner);
            slot.owner.stack.items[slot.stack_index] = value;
            self.gc.threadBarrier(slot.owner, value);
        },
        .closed => |*closed| {
            closed.* = value;
            self.gc.writeBarrier(upvalue, value);
        },
    }
}

pub fn closeUpvalues(self: *State, thread: *Thread, first_stack_index: usize) void {
    while (thread.open_upvalues) |upvalue| {
        const stack_index = upvalue.cell.open.stack_index;
        if (stack_index < first_stack_index) break;
        rollback_mod.touch(upvalue);
        rollback_mod.touch(thread);
        const value = thread.stack.items[stack_index];
        upvalue.cell = .{ .closed = value };
        self.gc.writeBarrier(upvalue, value);
        thread.open_upvalues = upvalue.next;
        upvalue.next = null;
    }
}

pub fn checkToBeClosedRegister(self: *State, thread: *Thread, register: bytecode.Register) !void {
    const value = vm_mod.get(self, thread, register);
    if (value == .nil) return;
    if (value == .boolean and !value.boolean) return;
    if ((try metatable_mod.getMetaEvent(self, value, .__close)) == null) {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        thread.stack.items[frame.base + register] = .nil;
        if (toBeClosedLocalName(self, thread, register)) |name| {
            const message = try std.fmt.allocPrint(self.allocator, "variable '{s}' got a non-closable value", .{name});
            defer self.allocator.free(message);
            return failure_mod.failRuntimeDetail(self, thread, message);
        }
        return failure_mod.failRuntimeDetail(self, thread, "variable got a non-closable value");
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

pub fn closeToBeClosedRegister(self: *State, thread: *Thread, register: bytecode.Register, error_value: ?Value) anyerror!void {
    const frame_count = thread.frames.items.len;
    const frame = thread.frames.items[thread.frames.items.len - 1];
    const absolute_register = frame.base + register;
    const value = thread.stack.items[absolute_register];
    if (value == .nil) return;
    if (value == .boolean and !value.boolean) return;
    const metamethod = (try metatable_mod.getMetaEvent(self, value, .__close)) orelse {
        thread.stack.items[absolute_register] = .nil;
        return self.fail("metamethod 'close'");
    };
    _ = (if (error_value) |err_value|
        call_mod.callOneNamed(self, thread, "close", "metamethod", metamethod, &.{ value, try call_mod.caughtErrorValue(self, err_value) })
    else
        call_mod.callOneNamed(self, thread, "close", "metamethod", metamethod, &.{value})) catch |err| {
        if (err == error.CoroutineYield and error_value != null) {
            thread.pending_unwind_error = error_value.?;
            self.gc.threadBarrier(thread, error_value.?);
            thread.pending_unwind_resume_frame_count = frame_count;
            thread.pending_unwind_target_frame_count = if (frame_count == 0) 0 else frame_count - 1;
        }
        if (call_mod.isRuntimeError(err)) {
            var close_err = err;
            call_mod.noteCaughtError(self, err);
            try call_mod.applyMessageHandler(self, thread);
            closeFramesTo(self, thread, frame_count, self.currentErrorValue()) catch |unwind_err| {
                close_err = unwind_err;
                if (!call_mod.isRuntimeError(unwind_err)) return unwind_err;
            };
            thread.stack.items[absolute_register] = .nil;
            return close_err;
        }
        thread.stack.items[absolute_register] = .nil;
        return err;
    };
    thread.stack.items[absolute_register] = .nil;
}

pub fn closeToBeClosedExitingPc(self: *State, thread: *Thread, frame_index: usize, source_pc: usize, target_pc: usize, error_value: ?Value) !void {
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
        if (value != .nil and !(value == .boolean and !value.boolean) and (try metatable_mod.getMetaEvent(self, value, .__close)) == null) continue;

        closeToBeClosedRegister(self, thread, local.register, pending_error) catch |err| {
            if (call_mod.isRuntimeError(err)) {
                discardFramesTo(self, thread, frame_index + 1);
                pending_error = self.currentErrorValue();
                close_failed = true;
            } else return err;
        };
    }

    if (close_failed) return self.rethrowValue(pending_error.?);
}

pub fn hasPendingToBeClosed(thread: *const Thread, frame: *const types.CallFrame, instruction_index: usize) bool {
    for (frame.proto.locals.items) |local| {
        if (!local.to_close or !localActiveAt(local, instruction_index)) continue;
        const value = thread.stack.items[frame.base + local.register];
        if (value != .nil and !(value == .boolean and !value.boolean)) return true;
    }
    return false;
}

pub fn closeActiveToBeClosedInTopFrame(self: *State, thread: *Thread, error_value: ?Value) !void {
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

        closeToBeClosedRegister(self, thread, local.register, pending_error) catch |err| {
            if (call_mod.isRuntimeError(err)) {
                discardFramesTo(self, thread, frame_index + 1);
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
        thread.native_call = call_mod.runtimeNativeCall(thread);
        closeActiveToBeClosedInTopFrame(self, thread, pending_error) catch |err| {
            pending_error = self.currentErrorValue();
            close_failed = close_failed or call_mod.isRuntimeError(err);
            if (!call_mod.isRuntimeError(err)) return err;
        };
        const frame = thread.frames.items[thread.frames.items.len - 1];
        closeUpvalues(self, thread, frame.base);
        thread.releaseFrame(&thread.frames.items[thread.frames.items.len - 1], self.allocator);
        thread.frames.items.len -= 1;
    }
    if (close_failed) return self.rethrowValue(pending_error.?);
}

fn discardFramesTo(self: *State, thread: *Thread, frame_count: usize) void {
    if (thread.frames.items.len > frame_count) abandonFramesAbove(thread, frame_count);
    while (thread.frames.items.len > frame_count) {
        const frame = thread.frames.items[thread.frames.items.len - 1];
        closeUpvalues(self, thread, frame.base);
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
