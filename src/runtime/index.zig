const std = @import("std");
const compile = @import("../compile.zig");
const stdlib = @import("../stdlib.zig");
const call_mod = @import("call.zig");
const coroutine_mod = @import("coroutine.zig");
const failure_mod = @import("failure.zig");
const metatable_mod = @import("metatable.zig");
const rollback_mod = @import("rollback.zig");
const state_mod = @import("state.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const State = state_mod.State;
const bytecode = compile.bytecode;
const max_metamethod_depth = state_mod.max_metamethod_depth;
const Value = types.Value;
const toInteger = value_mod.toInteger;
const indexErrorMessage = value_mod.indexErrorMessage;
const callErrorMessage = value_mod.callErrorMessage;
const floatToInteger = value_mod.floatToInteger;
const functionLike = value_mod.functionLike;
const Table = types.Table;
const Thread = types.Thread;

pub fn getTableFromThread(self: *State, thread: *Thread, table_value: Value, key_value: Value) !Value {
    return getTableDepth(self, thread, table_value, key_value, 0);
}

pub fn getTableToRegister(self: *State, thread: *Thread, dest: bytecode.Register, table_value: Value, key_value: Value) !void {
    const value = try getTableDepthContinuable(self, thread, vm_mod.absoluteRegister(self, thread, dest), table_value, key_value, 0);
    vm_mod.set(self, thread, dest, value);
}

fn getTableDepthContinuable(self: *State, thread: *Thread, dest: usize, table_value: Value, key_value: Value, depth: usize) !Value {
    if (depth > max_metamethod_depth) return self.fail("'__index' chain too long");
    const key = try readableTableKey(self, key_value) orelse return .nil;

    if (table_value == .table) {
        const value = table_value.table.get(key);
        if (value != .nil) return value;
    }

    const metamethod = try metatable_mod.getMetaEvent(self, table_value, .__index) orelse {
        if (table_value == .table) return .nil;
        return failure_mod.failIndexTypeError(self, thread, table_value);
    };

    return switch (metamethod) {
        .table => getTableDepthContinuable(self, thread, dest, metamethod, key, depth + 1),
        else => if (functionLike(metamethod))
            try call_mod.callOneMetamethodWithContinuation(self, thread, "__index", metamethod, &.{ table_value, key }, .{ .value = dest })
        else
            failure_mod.failRuntimeDetail(self, thread, indexErrorMessage(metamethod)),
    };
}

fn getTableDepth(self: *State, thread: ?*Thread, table_value: Value, key_value: Value, depth: usize) !Value {
    if (depth > max_metamethod_depth) return self.fail("'__index' chain too long");
    const key = try readableTableKey(self, key_value) orelse return .nil;

    if (table_value == .table) {
        const value = table_value.table.get(key);
        if (value != .nil) return value;
    }

    const metamethod = try metatable_mod.getMetaEvent(self, table_value, .__index) orelse {
        if (table_value == .table) return .nil;
        return failure_mod.failIndexTypeError(self, thread, table_value);
    };

    return switch (metamethod) {
        .table => getTableDepth(self, thread, metamethod, key, depth + 1),
        else => if (!functionLike(metamethod))
            failure_mod.failRuntimeDetail(self, thread, indexErrorMessage(metamethod))
        else if (thread) |active_thread|
            try call_mod.callOneMetamethod(self, active_thread, "__index", metamethod, &.{ table_value, key })
        else
            self.fail(callErrorMessage(metamethod)),
    };
}

pub fn rawGet(self: *State, table_value: Value, key_value: Value) !Value {
    const table = switch (table_value) {
        .table => |table| table,
        else => return self.fail(indexErrorMessage(table_value)),
    };
    const key = try readableTableKey(self, key_value) orelse return .nil;
    return table.get(key);
}

pub fn setTable(self: *State, table_value: Value, key_value: Value, value: Value) !void {
    try setTableDepth(self, null, table_value, key_value, value, 0);
}

pub fn setTableValue(self: *State, table_value: Value, key_value: Value, value: Value) !void {
    try setTable(self, table_value, key_value, value);
}

pub fn setTableFromThread(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value) !void {
    try setTableDepth(self, thread, table_value, key_value, value, 0);
}

pub fn setTableFromThreadContinuable(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value) !void {
    try setTableDepthContinuable(self, thread, table_value, key_value, value, 0);
}

fn setTableDepthContinuable(self: *State, thread: *Thread, table_value: Value, key_value: Value, value: Value, depth: usize) !void {
    if (depth > max_metamethod_depth) return self.fail("'__newindex' chain too long");
    const key = try writableTableKey(self, key_value);

    if (table_value == .table) {
        const table = table_value.table;
        if (table.rollback != null and table.get(key) != .nil) try rollback_mod.tableWritable(table);
        if (table.setExistingNonNil(key, value)) {
            self.gc.writeExistingKeyBarrier(table, key, value);
            return;
        }
    }

    const metamethod = try metatable_mod.getMetaEvent(self, table_value, .__newindex) orelse {
        if (table_value == .table) {
            try self.setTableRaw(table_value.table, key, value);
            return;
        }
        return failure_mod.failNewIndexTypeError(self, thread, table_value);
    };

    switch (metamethod) {
        .table => try setTableDepthContinuable(self, thread, metamethod, key, value, depth + 1),
        else => if (functionLike(metamethod)) {
            _ = try call_mod.callOneMetamethodWithContinuation(self, thread, "__newindex", metamethod, &.{ table_value, key, value }, .discard);
        } else {
            return failure_mod.failRuntimeDetail(self, thread, indexErrorMessage(metamethod));
        },
    }
}

fn setTableDepth(self: *State, thread: ?*Thread, table_value: Value, key_value: Value, value: Value, depth: usize) !void {
    if (depth > max_metamethod_depth) return self.fail("'__newindex' chain too long");
    const key = try writableTableKey(self, key_value);

    if (table_value == .table) {
        const table = table_value.table;
        if (table.rollback != null and table.get(key) != .nil) try rollback_mod.tableWritable(table);
        if (table.setExistingNonNil(key, value)) {
            self.gc.writeExistingKeyBarrier(table, key, value);
            return;
        }
    }

    const metamethod = try metatable_mod.getMetaEvent(self, table_value, .__newindex) orelse {
        if (table_value == .table) {
            try self.setTableRaw(table_value.table, key, value);
            return;
        }
        return failure_mod.failNewIndexTypeError(self, thread, table_value);
    };

    switch (metamethod) {
        .table => try setTableDepth(self, thread, metamethod, key, value, depth + 1),
        else => if (!functionLike(metamethod)) {
            return failure_mod.failRuntimeDetail(self, thread, indexErrorMessage(metamethod));
        } else if (thread) |active_thread| {
            _ = try call_mod.callOneMetamethod(self, active_thread, "__newindex", metamethod, &.{ table_value, key, value });
        } else {
            return self.fail(callErrorMessage(metamethod));
        },
    }
}

pub fn readableTableKey(self: *State, value: Value) !?Value {
    _ = self;
    return switch (value) {
        .nil => null,
        .number => |number| if (std.math.isNan(number)) null else if (floatToInteger(number)) |integer| .{ .integer = integer } else value,
        else => value,
    };
}

pub fn writableTableKey(self: *State, value: Value) !Value {
    return switch (value) {
        .nil => self.fail("table index is nil"),
        .number => |number| if (std.math.isNan(number)) self.fail("table index is NaN") else if (floatToInteger(number)) |integer| .{ .integer = integer } else value,
        else => value,
    };
}

pub fn rawLen(self: *State, value: Value) !Value {
    return switch (value) {
        .string => |string| .{ .integer = @intCast(string.len) },
        .table => |table| .{ .integer = table.len() },
        else => self.fail("table or string expected"),
    };
}

pub fn rawSet(self: *State, table_value: Value, key_value: Value, value: Value) !void {
    const table = try self.expectTable(table_value);
    const key = try writableTableKey(self, key_value);
    try self.setTableRaw(table, key, value);
}

pub fn nextValues(self: *State, table_value: Value, key_value: Value) ![2]Value {
    const table = try self.expectTable(table_value);
    const key = try readableTableKey(self, key_value) orelse Value.nil;
    return table.next(key) catch return self.fail("invalid key to 'next'");
}

pub fn callPairsMetamethod(self: *State, thread: *Thread, op: bytecode.Call, metamethod: Value, value: Value) !void {
    const frame_count = thread.frames.items.len;
    const relative_base = thread.scratchRegister();
    const source_base = thread.frames.items[frame_count - 1].base + @as(usize, relative_base);
    try thread.ensureStack(self.allocator, source_base + 4, call_mod.callStackValueLimit(self, thread));
    thread.stack.items[source_base] = metamethod;
    thread.stack.items[source_base + 1] = value;
    const continuation: types.PairsContinuation = .{
        .frame_count = frame_count,
        .source_base = source_base,
        .base = op.base,
        .return_count = op.return_count,
    };
    // Lua takes four results from __pairs; scratch registers keep padding off locals.
    call_mod.invokeValue(self, thread, .{ .base = relative_base, .arg_count = 1, .return_count = 4 }, 0) catch |err| {
        if (err == error.CoroutineYield) try pushPairsContinuation(self, thread, continuation);
        return err;
    };
    vm_mod.runThreadUntil(self, thread, frame_count) catch |err| {
        if (err == error.CoroutineYield) try pushPairsContinuation(self, thread, continuation);
        return err;
    };
    try returnPairsResults(self, thread, continuation);
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

pub fn completeReadyPairsContinuation(self: *State, thread: *Thread) !bool {
    for (thread.pairs_continuations.items, 0..) |continuation, index| {
        if (continuation.frame_count != thread.frames.items.len) continue;
        // A native protected __pairs can suspend at the same depth; finish that inner call first.
        if (call_mod.readyProtectedContinuationIndex(thread)) |protected_index| {
            if (thread.protected_continuations.items[protected_index].order < continuation.order) {
                return call_mod.completeReadyProtectedContinuation(self, thread);
            }
        }
        _ = thread.pairs_continuations.orderedRemove(index);
        thread.refreshContinuationFrameCount();
        try returnPairsResults(self, thread, continuation);
        return true;
    }
    return false;
}

pub fn ipairsIterValues(self: *State, thread: *Thread, table_value: Value, key_value: Value) ![2]Value {
    const current = toInteger(key_value) orelse return self.fail("invalid index to 'ipairs'");
    const next_index = current +% 1;
    const value = try getTableFromThread(self, thread, table_value, .{ .integer = next_index });
    if (value == .nil) return .{ .nil, .nil };
    return .{ .{ .integer = next_index }, value };
}

fn iteratorNativeCall(thread: *Thread, op: bytecode.GenericFor) types.NativeCall {
    return call_mod.nativeCallInfo(thread, .{ .base = op.base, .arg_count = 2, .return_count = 0 }, null, "for iterator", "for iterator", 0);
}

pub fn advanceGenericFor(self: *State, thread: *Thread, op: bytecode.GenericFor, jump_on_nil: bool) !bool {
    const iterator = vm_mod.get(self, thread, op.base);
    const state = vm_mod.get(self, thread, op.base + 1);
    const control = vm_mod.get(self, thread, op.base + 2);
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
            fixed = try nextValues(self, state, control);
            break :blk fixed[0..2];
        },
        .native_ipairs_iter => blk: {
            // Match invokeValue's native boundary, including __index calls.
            thread.native_call_depth += 1;
            defer thread.native_call_depth -= 1;
            fixed = try ipairsIterValues(self, thread, state, control);
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
                owned_values = call_mod.callCollect(self, thread, iterator, &args) catch |err| switch (err) {
                    error.CoroutineYield => {
                        try pushGenericForContinuation(self, thread, frame_count, op, jump_on_nil);
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
            owned_values = call_mod.callCollect(self, thread, iterator, &args) catch |err| switch (err) {
                error.CoroutineYield => {
                    try pushGenericForContinuation(self, thread, frame_count, op, jump_on_nil);
                    return err;
                },
                else => return err,
            };
            break :blk owned_values.?;
        },
    };
    return applyGenericForValues(self, thread, op, values);
}

fn applyGenericForValues(self: *State, thread: *Thread, op: bytecode.GenericFor, values: []const Value) !bool {
    const first_value = if (values.len > 0) values[0] else Value.nil;
    vm_mod.set(self, thread, op.base + 2, first_value);
    for (0..op.variable_count) |index| {
        const value = if (index < values.len) values[index] else Value.nil;
        vm_mod.set(self, thread, op.base + 4 + @as(bytecode.Register, @intCast(index)), value);
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

pub fn completeReadyGenericForContinuation(self: *State, thread: *Thread) !bool {
    const index = readyGenericForContinuationIndex(thread) orelse return false;
    const continuation = thread.generic_for_continuations.orderedRemove(index);
    thread.refreshContinuationFrameCount();
    const values = try coroutine_mod.copyStackSlice(self, thread, thread.last_result_base, thread.last_result_count);
    defer self.allocator.free(values);
    if (!(try applyGenericForValues(self, thread, continuation.op, values)) and continuation.jump_on_nil) {
        try vm_mod.jumpThread(self, thread, continuation.op.offset, false);
    }
    return true;
}

pub inline fn noIndexMetamethod(table: *const Table) bool {
    return metatable_mod.noMetaEvent(table, .__index);
}

pub inline fn noNewindexMetamethod(table: *const Table) bool {
    return metatable_mod.noMetaEvent(table, .__newindex);
}
