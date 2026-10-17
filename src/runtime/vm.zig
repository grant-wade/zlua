const std = @import("std");
const compile = @import("../compile.zig");
const stdlib = @import("../stdlib.zig");
const call_mod = @import("call.zig");
const debug_mod = @import("debug.zig");
const failure_mod = @import("failure.zig");
const gc_mod = @import("gc.zig");
const index_mod = @import("index.zig");
const load_mod = @import("load.zig");
const metatable_mod = @import("metatable.zig");
const operators_mod = @import("operators.zig");
const rollback_mod = @import("rollback.zig");
const State = @import("state.zig").State;
const state_mod = @import("state.zig");
const types = @import("types.zig");
const upvalue_mod = @import("upvalue.zig");
const table_index = @import("table_index.zig");
const value_mod = @import("value.zig");

const Thread = types.Thread;
const bytecode = compile.bytecode;
const proto_mod = compile.proto;
const lua_max_c_calls = state_mod.lua_max_c_calls;
const Value = types.Value;
const valuesEqual = value_mod.valuesEqual;
const truthy = value_mod.truthy;
const toInteger = value_mod.toInteger;
const toNumber = value_mod.toNumber;
const toNumberMaybe = value_mod.toNumberMaybe;
const parseIntegerLiteral = value_mod.parseIntegerLiteral;
const parseLuaNumber = value_mod.parseLuaNumber;
const arrayIndex = value_mod.arrayIndex;
const appendFmt = value_mod.appendFmt;
const Closure = types.Closure;
const Table = types.Table;
const CallFrame = types.CallFrame;

pub fn runThreadUntil(self: *State, thread: *Thread, target_frame_count: usize) anyerror!void {
    runThreadLoop(self, thread, target_frame_count) catch |err| {
        if (err == error.Interrupted and self.execution_depth == 0) self.budget.consumeInterrupt();
        return err;
    };
}

fn runThreadLoop(self: *State, thread: *Thread, target_frame_count: usize) anyerror!void {
    defer self.gc.syncThreadStorage(thread);
    self.gc.rememberObject(.{ .thread = thread });
    self.execution_depth += 1;
    defer self.execution_depth -= 1;
    if (self.execution_depth >= lua_max_c_calls) try call_mod.checkCStack(self, thread);
    try rollback_mod.threadWritable(thread);
    while (thread.frames.items.len > target_frame_count) {
        if (thread.pending_unwind_error != null or thread.pending_yield_hook_return or call_mod.hasPendingContinuations(thread)) {
            if (thread.pending_unwind_error != null and thread.frames.items.len == thread.pending_unwind_resume_frame_count) {
                const error_value = thread.pending_unwind_error.?;
                const target = thread.pending_unwind_target_frame_count;
                thread.pending_unwind_error = null;
                try upvalue_mod.closeFramesTo(self, thread, target, error_value);
                return self.rethrowValue(error_value);
            }
            if (thread.frames.items.len <= thread.continuation_frame_count) {
                if (try index_mod.completeReadyPairsContinuation(self, thread)) continue;
                if (try call_mod.completeReadyCallOneContinuation(self, thread)) continue;
                if (try call_mod.completeReadyProtectedContinuation(self, thread)) continue;
                if (try call_mod.completeReadyTailCallContinuation(self, thread)) continue;
                if (try index_mod.completeReadyGenericForContinuation(self, thread)) continue;
            }
            if (thread.pending_yield_hook_return) {
                thread.pending_yield_hook_return = false;
                try debug_mod.callHook(self, thread, "return");
                continue;
            }
        }
        var frame = &thread.frames.items[thread.frames.items.len - 1];
        const proto = frame.proto;
        if (frame.pc >= proto.instructions.items.len) {
            try call_mod.returnFromFrame(self, thread, 0, 0);
            continue;
        }
        const pc = frame.pc;
        const instruction = proto.instructions.items[pc];
        if (proto.fast_loop_entry and plainFastLoopCanStart(instruction) and try runPlainFastLoop(self, thread, target_frame_count)) continue;
        frame.pc += 1;
        try self.budget.checkLimits(thread);
        if (self.options.trace_vm) try traceInstruction(self, frame.*, pc, instruction);
        if (thread.hook != .nil) {
            try debug_mod.callLineHook(self, thread);
            try debug_mod.callCountHook(self, thread);
        }

        try executeInstruction(self, thread, proto, instruction);

        if (!instructionPreservesLastResult(instruction)) {
            thread.last_result_count = 0;
            thread.last_transfer_count = 0;
        }

        if (self.gc.running and (self.gc.shouldRunAuto() or self.stressPending())) try self.gc.autoStep(thread);
    }
}

fn executeInstruction(self: *State, thread: *Thread, proto: *const proto_mod.Proto, instruction: bytecode.Instruction) anyerror!void {
    const frame = &thread.frames.items[thread.frames.items.len - 1];
    const base = frame.base;
    const stack = thread.stack.items;
    switch (instruction) {
        .load_nil => |dest| stack[base + dest] = .nil,
        .load_bool => |op| stack[base + op.dest] = .{ .boolean = op.value },
        .load_const => |op| stack[base + op.dest] = try protoConstant(self, frame.closure, proto, op.constant),
        .move => |op| stack[base + op.dest] = stack[base + op.source],
        .get_global => |op| stack[base + op.register] = globalGet(self, proto, op.name),
        .set_global => |op| if (!fastGlobalSetExisting(self, proto, op.name, stack[base + op.register])) {
            try self.setGlobal(constantString(proto, op.name), stack[base + op.register]);
        },
        .declare_global => |op| try self.declareGlobal(thread, constantString(proto, op.name), op.table, op.value),
        .add => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawNumericBinaryOpFast(lhs, rhs, .add)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .add);
            }
        },
        .sub => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawNumericBinaryOpFast(lhs, rhs, .sub)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .sub);
            }
        },
        .mul => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawNumericBinaryOpFast(lhs, rhs, .mul)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .mul);
            }
        },
        .div => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawNumericBinaryOpFast(lhs, rhs, .div)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .div);
            }
        },
        .idiv => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawNumericBinaryOpFast(lhs, rhs, .idiv)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .idiv);
            }
        },
        .mod => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawNumericBinaryOpFast(lhs, rhs, .mod)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .mod);
            }
        },
        .pow => |op| try operators_mod.binaryOpToRegister(self, thread, op, .pow),
        .band => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawIntegerBitwiseOpFast(lhs, rhs, .band)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .band);
            }
        },
        .bor => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawIntegerBitwiseOpFast(lhs, rhs, .bor)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .bor);
            }
        },
        .bxor => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawIntegerBitwiseOpFast(lhs, rhs, .bxor)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .bxor);
            }
        },
        .shl => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawIntegerBitwiseOpFast(lhs, rhs, .shl)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .shl);
            }
        },
        .shr => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawIntegerBitwiseOpFast(lhs, rhs, .shr)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryOpToRegister(self, thread, op, .shr);
            }
        },
        .unm => |op| try operators_mod.unaryOpToRegister(self, thread, op, .unm),
        .bnot => |op| try operators_mod.unaryOpToRegister(self, thread, op, .bnot),
        .concat => |op| try operators_mod.binaryOpToRegister(self, thread, op, .concat),
        .concat_range => |op| try operators_mod.concatRangeToRegister(self, thread, op),
        .eq => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (!operators_mod.equalityHasMetamethod(lhs, rhs)) {
                stack[base + op.dest] = .{ .boolean = valuesEqual(lhs, rhs) };
            } else {
                try operators_mod.equalValuesToRegister(self, thread, op);
            }
        },
        .lt => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawCompare(lhs, rhs, .lt)) |result| {
                stack[base + op.dest] = .{ .boolean = result };
            } else {
                try operators_mod.compareValuesToRegister(self, thread, op, .lt);
            }
        },
        .le => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawCompare(lhs, rhs, .le)) |result| {
                stack[base + op.dest] = .{ .boolean = result };
            } else {
                try operators_mod.compareValuesToRegister(self, thread, op, .le);
            }
        },
        .not => |op| {
            const result = !truthy(stack[base + op.source]);
            stack[base + op.dest] = .{ .boolean = result };
        },
        .len => |op| try operators_mod.lengthToRegister(self, thread, op),
        .new_table => |op| stack[base + op.dest] = try self.newTableWithHints(op.array_hint, op.hash_hint),
        .set_list => |op| try setList(self, thread, op),
        .get_table => |op| {
            const table_value = stack[base + op.table];
            const key_value = stack[base + op.key];
            if (frame.named_vararg_readonly and op.table == proto.param_count) {
                stack[base + op.dest] = call_mod.namedVarargRead(frame.varargs, key_value);
            } else if (fastTableRawGet(table_value, key_value)) |value| {
                stack[base + op.dest] = value;
            } else {
                try index_mod.getTableToRegister(self, thread, op.dest, table_value, key_value);
            }
        },
        .set_table => |op| {
            const table_value = stack[base + op.table];
            const key_value = stack[base + op.key];
            const value = stack[base + op.value];
            if (!try fastTableArraySet(self, table_value, key_value, value)) {
                if (key_value != .string or !try fastTableKnownKeySet(self, table_value, key_value, value)) {
                    try index_mod.setTableFromThreadContinuable(self, thread, table_value, key_value, value);
                }
            }
        },
        .set_array => |op| {
            const table_value = stack[base + op.table];
            const value = stack[base + op.value];
            if (table_value == .table and op.index != 0) {
                try setTableArrayRawIndex(self, table_value.table, op.index, value);
            } else {
                try index_mod.setTableFromThreadContinuable(self, thread, table_value, .{ .integer = @intCast(op.index) }, value);
            }
        },
        .get_field => |op| {
            const table_value = stack[base + op.table];
            const key = Value{ .string = constantString(proto, op.name) };
            if (frame.named_vararg_readonly and op.table == proto.param_count) {
                stack[base + op.dest] = call_mod.namedVarargRead(frame.varargs, key);
            } else if (fastTableFieldGet(table_value, key.string, proto.constant_hashes[op.name])) |value| {
                stack[base + op.dest] = value;
            } else {
                try index_mod.getTableToRegister(self, thread, op.dest, table_value, key);
            }
        },
        .set_field => |op| {
            const table_value = stack[base + op.table];
            const key = Value{ .string = constantString(proto, op.name) };
            const value = stack[base + op.value];
            if (!fastTableKnownKeySetExistingNoAlloc(self, table_value, key, proto.constant_hashes[op.name], value) and
                !try fastTableKnownKeySet(self, table_value, key, value))
            {
                try index_mod.setTableFromThreadContinuable(self, thread, table_value, key, value);
            }
        },
        .jmp => |offset| try jumpThreadMaybeFast(self, thread, offset, true),
        .compare_branch => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            if (operators_mod.rawCompareBranchResult(lhs, rhs, op.op)) |result| {
                if (result == op.jump_if_truthy) try jumpThreadMaybeFast(self, thread, op.offset, true);
            } else {
                try operators_mod.compareBranch(self, thread, op);
            }
        },
        .test_op => |op| if (truthy(stack[base + op.register]) == op.jump_if_truthy) {
            try jumpThreadMaybeFast(self, thread, op.offset, true);
        },
        .test_set => |op| {
            const value = stack[base + op.source];
            stack[base + op.dest] = value;
            if (truthy(value) == op.jump_if_truthy) {
                try jumpThreadMaybeFast(self, thread, op.offset, true);
            }
        },
        .call => |op| try call_mod.callValue(self, thread, op),
        .tail_call => |op| try call_mod.tailCallValue(self, thread, op),
        .ret => |op| try call_mod.returnFromFrame(self, thread, op.first, op.count),
        .vararg => |op| try call_mod.loadVarargs(self, thread, op),
        .for_prep => |op| try forPrep(self, thread, op),
        .for_loop => |op| try forLoop(self, thread, op),
        .tfor_prep => |op| if (!(try index_mod.advanceGenericFor(self, thread, op, true))) try jumpThread(self, thread, op.offset, false),
        .tfor_call => |op| _ = try index_mod.advanceGenericFor(self, thread, op, false),
        .tfor_loop => |op| try jumpThread(self, thread, op.offset, false),
        .closure => |op| stack[base + op.dest] = try self.newClosure(thread, proto.children.items[op.proto]),
        .get_upvalue => |op| stack[base + op.register] = upvalue_mod.readUpvalue(self, thread, op.upvalue),
        .set_upvalue => |op| try upvalue_mod.writeUpvalue(self, thread, op.upvalue, stack[base + op.register]),
        .close => |register| if (thread.open_upvalues != null) upvalue_mod.closeUpvalues(self, thread, base + register),
        .check_close => |register| try upvalue_mod.checkToBeClosedRegister(self, thread, register),
        .close_tbc => |register| try upvalue_mod.closeToBeClosedRegister(self, thread, register, null),
    }
}

fn runPlainFastLoop(self: *State, thread: *Thread, target_frame_count: usize) anyerror!bool {
    if (thread.frames.items.len <= target_frame_count) return false;
    if (self.budget.active() or self.options.trace_vm) return false;
    if (self.budget.fastLoopInterrupted()) return false;
    if (self.stressPending()) return false;
    if (thread.hook != .nil and (thread.hook_line or thread.hook_count != 0 or thread.hook_running)) return false;
    if (self.gc.running and self.gc.shouldRunAuto()) return false;

    var stack_limit = @min(thread.stack.items.len, self.stackValueLimit());
    var frame_limit = @min(thread.frames.capacity, self.callFrameLimit());
    var return_floor = fastReturnFloor(thread, target_frame_count);

    var frame_index = thread.frames.items.len - 1;
    var frame = &thread.frames.items[frame_index];
    var proto = frame.proto;
    var pc = frame.pc;
    var base = frame.base;
    var count_bias: u64 = 0 -% pc;
    defer self.budget.instructions = self.budget.instructions +| (pc +% count_bias);
    var segment_start: u64 = 0;
    // Executed-instruction total after a general operation, which may have changed frames.
    var resync: ?u64 = null;
    frames: while (true) {
        if (resync) |executed| {
            @branchHint(.unlikely);
            resync = null;
            if (!try fastLoopCanResume(self, thread, target_frame_count)) return true;
            frame_index = thread.frames.items.len - 1;
            frame = &thread.frames.items[frame_index];
            proto = frame.proto;
            pc = frame.pc;
            count_bias = executed -% pc;
            base = frame.base;
            stack_limit = @min(thread.stack.items.len, self.stackValueLimit());
            frame_limit = @min(thread.frames.capacity, self.callFrameLimit());
            return_floor = fastReturnFloor(thread, target_frame_count);
        }
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
                    if (upvalue.owner != thread) self.gc.rememberObject(.{ .thread = upvalue.owner });
                } else {
                    rollback_mod.touch(upvalue);
                    upvalue.closed = stack[op.register];
                    self.gc.writeBarrier(upvalue, upvalue.closed);
                }
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .add => {
                const op = instructions[pc].add;
                const value = operators_mod.rawNumericBinaryOpFast(stack[op.left], stack[op.right], .add) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .sub => {
                const op = instructions[pc].sub;
                const value = operators_mod.rawNumericBinaryOpFast(stack[op.left], stack[op.right], .sub) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .mul => {
                const op = instructions[pc].mul;
                const value = operators_mod.rawNumericBinaryOpFast(stack[op.left], stack[op.right], .mul) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .div => {
                const op = instructions[pc].div;
                const value = operators_mod.rawNumericBinaryOpFast(stack[op.left], stack[op.right], .div) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .idiv => {
                const op = instructions[pc].idiv;
                const value = operators_mod.rawNumericBinaryOpFast(stack[op.left], stack[op.right], .idiv) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .mod => {
                const op = instructions[pc].mod;
                const value = operators_mod.rawNumericBinaryOpFast(stack[op.left], stack[op.right], .mod) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .band => {
                const op = instructions[pc].band;
                const value = operators_mod.rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .band) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .bor => {
                const op = instructions[pc].bor;
                const value = operators_mod.rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .bor) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .bxor => {
                const op = instructions[pc].bxor;
                const value = operators_mod.rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .bxor) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .shl => {
                const op = instructions[pc].shl;
                const value = operators_mod.rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .shl) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .shr => {
                const op = instructions[pc].shr;
                const value = operators_mod.rawIntegerBitwiseOpFast(stack[op.left], stack[op.right], .shr) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .eq => {
                const op = instructions[pc].eq;
                const lhs = stack[op.left];
                const rhs = stack[op.right];
                if (operators_mod.equalityHasMetamethod(lhs, rhs) and !valuesEqual(lhs, rhs)) break :fast_loop;
                stack[op.dest] = .{ .boolean = valuesEqual(lhs, rhs) };
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .lt => {
                const op = instructions[pc].lt;
                const result = operators_mod.rawCompare(stack[op.left], stack[op.right], .lt) orelse break :fast_loop;
                stack[op.dest] = .{ .boolean = result };
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .le => {
                const op = instructions[pc].le;
                const result = operators_mod.rawCompare(stack[op.left], stack[op.right], .le) orelse break :fast_loop;
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
                const table_value = stack[op.table];
                const key = stack[op.key];
                const value = if (frame.named_vararg_readonly and op.table == proto.param_count)
                    call_mod.namedVarargRead(frame.varargs, key)
                else if (arrayValue(table_value, key)) |hit|
                    hit
                else
                    fastTableRawGet(table_value, key) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .get_field => {
                const op = instructions[pc].get_field;
                const key = Value{ .string = constantString(proto, op.name) };
                const value = if (frame.named_vararg_readonly and op.table == proto.param_count)
                    call_mod.namedVarargRead(frame.varargs, key)
                else if (stack[op.table] == .string)
                    stringMethod(self, key.string, proto.constant_hashes[op.name]) orelse break :fast_loop
                else
                    fastTableFieldGet(stack[op.table], key.string, proto.constant_hashes[op.name]) orelse break :fast_loop;
                stack[op.dest] = value;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_table => {
                const op = instructions[pc].set_table;
                if (arraySlot(stack[op.table], stack[op.key])) |slot| {
                    const table = stack[op.table].table;
                    slot.* = stack[op.value];
                    writeTableBarrierFast(self, table, stack[op.key], stack[op.value]);
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                }
                if (!fastTableArraySetExistingNoAlloc(self, stack[op.table], stack[op.key], stack[op.value]) and
                    !fastTableDynamicKeySetNoAlloc(self, stack[op.table], stack[op.key], stack[op.value])) break :fast_loop;
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
                self.gc.writeTableBarrier(table, .{ .integer = @intCast(index) }, value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_field => {
                const op = instructions[pc].set_field;
                const key = Value{ .string = constantString(proto, op.name) };
                if (!fastTableKnownKeySetExistingNoAlloc(self, stack[op.table], key, proto.constant_hashes[op.name], stack[op.value])) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .compare_branch => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const op = instructions[pc].compare_branch;
                const lhs = stack[op.left];
                const rhs = stack[op.right];
                const result = if (lhs == .integer and rhs == .integer) switch (op.op) {
                    .eq => lhs.integer == rhs.integer,
                    .lt => lhs.integer < rhs.integer,
                    .le => lhs.integer <= rhs.integer,
                } else operators_mod.rawCompareBranchResult(lhs, rhs, op.op) orelse break :fast_loop;
                pc += 1;
                if (result == op.jump_if_truthy) {
                    const source_pc = pc;
                    pc = jumpTarget(source_pc, op.offset);
                    count_bias +%= source_pc -% pc;
                    if (pc < source_pc) {
                        frame.last_hook_line = null;
                        if (self.budget.fastLoopInterrupted()) break :fast_loop;
                    }
                }
                if (pc >= instructions.len) break :fast_loop;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .jmp => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const offset = instructions[pc].jmp;
                pc += 1;
                const source_pc = pc;
                pc = jumpTarget(source_pc, offset);
                count_bias +%= source_pc -% pc;
                if (pc < source_pc) {
                    frame.last_hook_line = null;
                    if (self.budget.fastLoopInterrupted()) break :fast_loop;
                }
                if (pc >= instructions.len) break :fast_loop;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .test_op => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const op = instructions[pc].test_op;
                pc += 1;
                if (truthy(stack[op.register]) == op.jump_if_truthy) {
                    const source_pc = pc;
                    pc = jumpTarget(source_pc, op.offset);
                    count_bias +%= source_pc -% pc;
                    if (pc < source_pc) {
                        frame.last_hook_line = null;
                        if (self.budget.fastLoopInterrupted()) break :fast_loop;
                    }
                }
                if (pc >= instructions.len) break :fast_loop;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .test_set => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
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
                        if (self.budget.fastLoopInterrupted()) break :fast_loop;
                    }
                }
                if (pc >= instructions.len) break :fast_loop;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .for_loop => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
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
                        if (self.budget.fastLoopInterrupted()) break :fast_loop;
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
                if (callee == .native and !thread.hook_return and op.arg_count != 0 and @as(usize, op.base) + 1 < stack.len) math: {
                    const result = stdlib.math.fastUnaryResult(callee.native, stack[op.base + 1]) orelse break :math;
                    const return_count: usize = if (op.return_count == bytecode.multret_count) 1 else op.return_count;
                    const absolute_base = base + op.base;
                    const stored_end = absolute_base + @max(return_count, 1);
                    if (stored_end > stack_limit) break :math;
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
                if (callee != .closure or !callee.closure.proto.fast_loop_call) {
                    // Natives and frames needing setup run through the general call path in place.
                    @branchHint(.unlikely);
                    if (thread.hook != .nil) break :fast_loop;
                    if (pc +% count_bias != segment_start) {
                        thread.last_result_count = 0;
                        thread.last_transfer_count = 0;
                    }
                    pc += 1;
                    frame.pc = pc;
                    segment_start = pc +% count_bias;
                    try call_mod.callValue(self, thread, op);
                    resync = segment_start;
                    continue :frames;
                }
                const closure = callee.closure;
                const callee_proto = closure.proto;
                const callee_index = frame_index + 1;
                if (callee_index >= frame_limit) break :fast_loop;
                const function_slot = base + op.base;
                const callee_base = function_slot + 1;
                const register_count = @max(callee_proto.max_registers, 1);
                const stack_end = callee_base + register_count;
                if (stack_end > stack_limit) break :fast_loop;

                const executed_count = pc +% count_bias -% segment_start;
                const copied = @min(op.arg_count, callee_proto.param_count);
                clearRegisters(thread.stack.items[callee_base + copied .. stack_end]);
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
                if (self.budget.fastLoopInterrupted()) return true;
                continue :frames;
            },
            .new_table => {
                const op = instructions[pc].new_table;
                pc += 1;
                frame.pc = pc;
                stack[op.dest] = try self.newTableWithHints(op.array_hint, op.hash_hint);
                if (self.gc.running and self.gc.shouldRunAuto()) {
                    resync = pc +% count_bias;
                    continue :frames;
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_list => {
                const op = instructions[pc].set_list;
                if (op.count == bytecode.multret_count and pc +% count_bias != segment_start) break :fast_loop;
                pc += 1;
                frame.pc = pc;
                try setList(self, thread, op);
                resync = pc +% count_bias;
                continue :frames;
            },
            .tail_call => {
                const op = instructions[pc].tail_call;
                if (thread.hook != .nil or op.arg_count == bytecode.multret_arg_count) break :fast_loop;
                if (pc +% count_bias != segment_start) {
                    thread.last_result_count = 0;
                    thread.last_transfer_count = 0;
                }
                pc += 1;
                frame.pc = pc;
                segment_start = pc +% count_bias;
                try call_mod.tailCallValue(self, thread, op);
                resync = segment_start;
                continue :frames;
            },
            .ret => {
                const op = instructions[pc].ret;
                // Returning onto the floor frame is fine, but the outer loop must take over afterwards.
                if (frame_index < return_floor or frame_index == 0) break :fast_loop;
                const open_here = if (thread.open_upvalues) |upvalue| upvalue.stack_index >= base else false;
                if (proto.has_to_close_locals or op.count == bytecode.multret_count or frame.return_count == bytecode.multret_count or
                    frame.owns_varargs or frame.pending_returns != null or open_here)
                {
                    @branchHint(.unlikely);
                    if (thread.hook != .nil) break :fast_loop;
                    if (pc +% count_bias != segment_start) {
                        thread.last_result_count = 0;
                        thread.last_transfer_count = 0;
                    }
                    pc += 1;
                    frame.pc = pc;
                    segment_start = pc +% count_bias;
                    try call_mod.returnFromFrame(self, thread, op.first, op.count);
                    resync = segment_start;
                    continue :frames;
                }
                const return_start = frame.return_start;
                const return_count = frame.return_count;
                if (return_start + return_count > stack_limit) break :fast_loop;
                const executed_count = pc +% count_bias -% segment_start;
                const copied = @min(return_count, op.count);
                for (0..copied) |index| thread.stack.items[return_start + index] = stack[op.first + index];
                clearRegisters(thread.stack.items[return_start + copied .. return_start + return_count]);
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
                if (frame_index + 1 == return_floor or self.budget.fastLoopInterrupted()) return true;
                continue :frames;
            },
            .close => {
                const first = base + instructions[pc].close;
                if (thread.open_upvalues) |upvalue| if (upvalue.stack_index >= first) upvalue_mod.closeUpvalues(self, thread, first);
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

/// Small frames clear their registers inline; a `memset` call costs more than the stores.
inline fn clearRegisters(registers: []Value) void {
    if (registers.len > 16) return @memset(registers, .nil);
    for (registers) |*register| register.* = .nil;
}

inline fn arrayValue(table_value: Value, key: Value) ?Value {
    if (table_value != .table or key != .integer) return null;
    const table = table_value.table;
    const index: u64 = @bitCast(key.integer -% 1);
    if (index >= table.array.items.len) return null;
    const value = table.array.items[@intCast(index)];
    return if (value != .nil) value else null;
}

/// Slot of an existing non-nil array element that a raw write may replace.
inline fn arraySlot(table_value: Value, key: Value) ?*Value {
    if (table_value != .table or key != .integer) return null;
    const table = table_value.table;
    const index: u64 = @bitCast(key.integer -% 1);
    if (index >= table.array.items.len) return null;
    if (table.rollback) |record| if (!record.header.detached) return null;
    const slot = &table.array.items[@intCast(index)];
    return if (slot.* != .nil) slot else null;
}

/// `Gc.writeTableBarrier` for non-string keys, skipping the call when it would do nothing.
inline fn writeTableBarrierFast(self: *State, table: *Table, key: Value, value: Value) void {
    const meta = &table.gc;
    if (self.gc.phase == .pause and meta.generation == self.gc.generation and (meta.age != .old or meta.remembered)) return;
    self.gc.writeTableBarrier(table, key, value);
}

fn fastReturnFloor(thread: *const Thread, target_frame_count: usize) usize {
    if (thread.pending_unwind_error != null or thread.pending_yield_hook_return or thread.hook_return) return std.math.maxInt(usize);
    if (call_mod.hasPendingContinuations(thread)) return @max(target_frame_count, thread.continuation_frame_count);
    return target_frame_count;
}

/// After a general call from the fast loop: runs a due collector step, then reports
/// whether the fast loop may continue with the thread's new top frame.
noinline fn fastLoopCanResume(self: *State, thread: *Thread, target_frame_count: usize) !bool {
    if (self.gc.running and (self.gc.shouldRunAuto() or self.stressPending())) try self.gc.autoStep(thread);
    const frame_count = thread.frames.items.len;
    if (frame_count <= target_frame_count) return false;
    if (thread.pending_unwind_error != null or thread.pending_yield_hook_return) return false;
    if (call_mod.hasPendingContinuations(thread) and frame_count <= thread.continuation_frame_count) return false;
    if (thread.hook != .nil or self.budget.active() or self.options.trace_vm or self.budget.fastLoopInterrupted() or self.stressPending()) return false;
    return thread.frames.items[frame_count - 1].pc < thread.frames.items[frame_count - 1].proto.instructions.items.len;
}

fn fastTableArraySet(self: *State, table_value: Value, key_value: Value, value: Value) !bool {
    if (table_value != .table) return false;
    const index = arrayIndex(key_value) orelse return false;
    if (index > std.math.maxInt(u32)) return false;
    return fastTableArraySetIndex(self, table_value, @intCast(index), value);
}

fn fastTableArraySetExistingNoAlloc(self: *State, table_value: Value, key_value: Value, value: Value) bool {
    if (table_value != .table) return false;
    const index = arrayIndex(key_value) orelse return false;
    const table = table_value.table;
    if (table.rollback) |record| if (!record.header.detached) return false;
    if (index <= table.array.items.len) {
        const slot = &table.array.items[index - 1];
        if (slot.* == .nil and !index_mod.noNewindexMetamethod(table)) return false;
        slot.* = value;
        self.gc.writeTableBarrier(table, key_value, value);
        return true;
    }
    if (value == .nil or !index_mod.noNewindexMetamethod(table)) return false;
    if (index == table.array.items.len + 1 and index <= table.array.capacity) {
        table.array.appendAssumeCapacity(value);
        table.removeHashKey(key_value);
        self.gc.writeTableBarrier(table, key_value, value);
        return true;
    }
    return false;
}

noinline fn fastTableDynamicKeySetNoAlloc(self: *State, table_value: Value, key: Value, value: Value) bool {
    if (key != .string) return false;
    return fastTableKnownKeySetExistingNoAlloc(self, table_value, key, table_index.hashStringKey(key.string), value);
}

/// `key` must be a string and `hash` its `table_index.hashStringKey`.
fn fastTableKnownKeySetExistingNoAlloc(self: *State, table_value: Value, key: Value, hash: u32, value: Value) bool {
    if (table_value != .table) return false;
    const table = table_value.table;
    if (table.rollback) |record| if (!record.header.detached) return false;
    if (table.findStringEntry(key.string, hash)) |index| {
        const slot = &table.entries.items[index].value;
        if (slot.* == .nil) {
            if (!index_mod.noNewindexMetamethod(table)) return false;
            table.invalidateMetaEvents();
        }
        slot.* = value;
        self.gc.writeTableBarrier(table, key, value);
        return true;
    }
    if (!index_mod.noNewindexMetamethod(table) or !table.insertHashEntryNoAlloc(key, value)) return false;
    self.gc.writeTableBarrier(table, key, value);
    return true;
}

fn fastTableArraySetIndex(self: *State, table_value: Value, index_u32: u32, value: Value) !bool {
    if (table_value != .table or index_u32 == 0) return false;
    const index: usize = index_u32;
    const key_value = Value{ .integer = @intCast(index_u32) };
    const table = table_value.table;
    defer self.gc.noteTableCapacityDelta(table, 0);
    try rollback_mod.tableWritable(table);
    if (index <= table.array.items.len) {
        const slot = &table.array.items[index - 1];
        if (slot.* != .nil or index_mod.noNewindexMetamethod(table)) {
            slot.* = value;
            self.gc.writeTableBarrier(table, key_value, value);
            return true;
        }
        return false;
    }
    if (value == .nil or !index_mod.noNewindexMetamethod(table)) return false;
    if (index == table.array.items.len + 1) {
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        try table.array.append(self.allocator, value);
        table.removeHashKey(key_value);
        self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
        self.gc.writeTableBarrier(table, key_value, value);
        return true;
    }
    if (index > table.array.capacity) return false;

    const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
    const old_len = table.array.items.len;
    try table.array.resize(self.allocator, index);
    @memset(table.array.items[old_len..], .nil);
    table.array.items[index - 1] = value;
    table.removeHashKey(key_value);
    self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
    self.gc.writeTableBarrier(table, key_value, value);
    return true;
}

fn setTableArrayRawIndex(self: *State, table: *Table, index_u32: u32, value: Value) !void {
    defer self.gc.noteTableCapacityDelta(table, 0);
    try rollback_mod.tableWritable(table);
    const index: usize = index_u32;
    const key = Value{ .integer = @intCast(index_u32) };
    if (index <= table.array.items.len) {
        table.array.items[index - 1] = value;
        self.gc.writeTableBarrier(table, key, value);
        return;
    }
    if (value == .nil) return;
    if (index == table.array.items.len + 1) {
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        try table.array.append(self.allocator, value);
        self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
        self.gc.writeTableBarrier(table, key, value);
        return;
    }
    if (index <= table.array.capacity) {
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        const old_len = table.array.items.len;
        try table.array.resize(self.allocator, index);
        @memset(table.array.items[old_len..], .nil);
        table.array.items[index - 1] = value;
        self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
        self.gc.writeTableBarrier(table, key, value);
        return;
    }
    try self.setTableRaw(table, key, value);
    self.gc.writeTableBarrier(table, key, value);
}

fn fastTableKnownKeySet(self: *State, table_value: Value, key: Value, value: Value) !bool {
    if (table_value != .table) return false;
    const table = table_value.table;
    if (table.rollback != null and table.get(key) != .nil) {
        try rollback_mod.tableWritable(table);
        self.gc.noteTableCapacityDelta(table, 0);
    }
    if (table.setExistingNonNil(key, value)) {
        self.gc.writeTableBarrier(table, key, value);
        return true;
    }
    if (!index_mod.noNewindexMetamethod(table)) return false;
    if (value == .nil) return true;
    try self.setTableRaw(table, key, value);
    self.gc.writeTableBarrier(table, key, value);
    return true;
}

fn traceInstruction(self: *State, frame: CallFrame, pc: usize, instruction: bytecode.Instruction) !void {
    const line = if (pc < frame.proto.line_info.items.len) frame.proto.line_info.items[pc].line else 0;
    try appendFmt(self.allocator, &self.stderr, "[trace-vm] {s}:{d} pc={d} op={s}\n", .{ frame.proto.source_name, line, pc, @tagName(instruction) });
}

pub fn get(_: *State, thread: *Thread, register: usize) Value {
    const frame = thread.frames.items[thread.frames.items.len - 1];
    return thread.stack.items[frame.base + register];
}

pub fn set(_: *State, thread: *Thread, register: usize, value: Value) void {
    const frame = thread.frames.items[thread.frames.items.len - 1];
    thread.stack.items[frame.base + register] = value;
}

pub fn absoluteRegister(_: *State, thread: *Thread, register: usize) usize {
    const frame = thread.frames.items[thread.frames.items.len - 1];
    return frame.base + @as(usize, register);
}

fn loadConstant(self: *State, constant: bytecode.Constant) !Value {
    return switch (constant) {
        .nil => .nil,
        .boolean => |value| .{ .boolean = value },
        .integer => |lexeme| try parseIntegerLiteral(lexeme),
        .number => |lexeme| .{ .number = try parseLuaNumber(lexeme) },
        .string => |lexeme| .{ .string = try load_mod.decodeStringLiteral(self, lexeme) },
    };
}

inline fn protoConstant(self: *State, closure: *Closure, proto: *const proto_mod.Proto, index: bytecode.ConstantIndex) !Value {
    if (index < proto.constant_values.len) {
        const decoded = proto.constant_values[index];
        if (decoded != .string) return decoded;
    }
    return closureConstant(self, closure, index);
}

fn closureConstant(self: *State, closure: *Closure, index: bytecode.ConstantIndex) !Value {
    if (closure.constants) |cache| if (cache[index]) |value| return value;
    try rollback_mod.closureWritable(closure);
    if (closure.constants == null) closure.constants = try allocateConstantCache(self, closure.proto);
    const constants = closure.constants.?;
    if (constants[index] == null) constants[index] = try loadConstant(self, closure.proto.constants.items[index]);
    self.gc.writeBarrier(closure, constants[index].?);
    return constants[index].?;
}

fn allocateConstantCache(self: *State, proto: *const proto_mod.Proto) ![]?Value {
    const constants = try self.allocator.alloc(?Value, proto.constants.items.len);
    errdefer self.allocator.free(constants);
    @memset(constants, null);
    self.gc.noteAllocation(constants.len * @sizeOf(?Value));
    return constants;
}

pub fn jumpThread(self: *State, thread: *Thread, offset: bytecode.JumpOffset, auto_gc: bool) !void {
    const frame_index = thread.frames.items.len - 1;
    const frame = &thread.frames.items[frame_index];
    const source_pc = frame.pc;
    const target_pc = jumpTarget(source_pc, offset);
    if (frame.proto.has_to_close_locals) try upvalue_mod.closeToBeClosedExitingPc(self, thread, frame_index, source_pc, target_pc, null);
    thread.frames.items[frame_index].pc = target_pc;
    if (target_pc < source_pc) {
        thread.frames.items[frame_index].last_hook_line = null;
        if (auto_gc and self.gc.running and self.gc.shouldRunAuto()) try self.gc.autoStep(thread);
    }
}

pub fn jumpThreadMaybeFast(self: *State, thread: *Thread, offset: bytecode.JumpOffset, auto_gc: bool) !void {
    const frame = &thread.frames.items[thread.frames.items.len - 1];
    if (frame.proto.has_to_close_locals) return jumpThread(self, thread, offset, auto_gc);

    const source_pc = frame.pc;
    const target_pc = jumpTarget(source_pc, offset);
    frame.pc = target_pc;
    if (target_pc < source_pc) {
        frame.last_hook_line = null;
        if (auto_gc and self.gc.running and self.gc.shouldRunAuto()) try self.gc.autoStep(thread);
    }
}

fn forPrep(self: *State, thread: *Thread, op: bytecode.ForLoop) !void {
    const initial = get(self, thread, op.base);
    const limit = get(self, thread, op.base + 1);
    const step = get(self, thread, op.base + 2);
    if (toInteger(initial)) |initial_integer| {
        if (toInteger(step)) |step_integer| {
            if (step_integer == 0) return failure_mod.failRuntimeDetail(self, thread, "'for' step is zero");
            const limit_integer = toInteger(limit) orelse blk: {
                const limit_number = toNumberMaybe(limit) orelse return failure_mod.failForTypeError(self, thread, .limit, limit);
                break :blk integerForLimit(limit_number, step_integer) orelse {
                    set(self, thread, op.base, .{ .integer = initial_integer });
                    set(self, thread, op.base + 1, .{ .integer = initial_integer });
                    set(self, thread, op.base + 2, .{ .integer = step_integer });
                    try jumpThread(self, thread, op.offset, false);
                    return;
                };
            };
            set(self, thread, op.base, .{ .integer = initial_integer });
            set(self, thread, op.base + 1, .{ .integer = limit_integer });
            set(self, thread, op.base + 2, .{ .integer = step_integer });
            if (!forLoopContinuesInteger(initial_integer, limit_integer, step_integer)) try jumpThread(self, thread, op.offset, false);
            return;
        }
    }

    const initial_number = toNumberMaybe(initial) orelse return failure_mod.failForTypeError(self, thread, .initial, initial);
    const limit_number = toNumberMaybe(limit) orelse return failure_mod.failForTypeError(self, thread, .limit, limit);
    const step_number = toNumberMaybe(step) orelse return failure_mod.failForTypeError(self, thread, .step, step);
    if (step_number == 0) return failure_mod.failRuntimeDetail(self, thread, "'for' step is zero");
    set(self, thread, op.base, .{ .number = initial_number });
    set(self, thread, op.base + 1, .{ .number = limit_number });
    set(self, thread, op.base + 2, .{ .number = step_number });
    if (!forLoopContinuesNumber(initial_number, limit_number, step_number)) try jumpThread(self, thread, op.offset, false);
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
                try jumpThread(self, thread, op.offset, false);
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
            try jumpThread(self, thread, op.offset, false);
        } else {
            const source_pc = frame.pc;
            const target_pc = jumpTarget(source_pc, op.offset);
            frame.pc = target_pc;
            if (target_pc < source_pc) frame.last_hook_line = null;
        }
    }
}

fn setList(self: *State, thread: *Thread, op: bytecode.SetList) !void {
    const frame = thread.frames.items[thread.frames.items.len - 1];
    const source_start = frame.base + op.first;
    const count: usize = if (op.count == bytecode.multret_count) try call_mod.resolveResultCount(self, thread, source_start, bytecode.multret_count) else op.count;
    const table_value = get(self, thread, op.table);
    if (try fastSetListRaw(self, thread, table_value, source_start, count, op.start_index)) return;
    for (0..count) |index| {
        const array_index = @as(usize, op.start_index) + index;
        try index_mod.setTable(self, table_value, .{ .integer = @intCast(array_index) }, thread.stack.items[source_start + index]);
    }
}

fn fastSetListRaw(self: *State, thread: *Thread, table_value: Value, source_start: usize, count: usize, start_index_u32: u32) !bool {
    if (table_value != .table or start_index_u32 == 0) return false;
    const table = table_value.table;
    defer self.gc.noteTableCapacityDelta(table, 0);
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
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        const old_len = table.array.items.len;
        try table.array.resize(self.allocator, grow_to);
        @memset(table.array.items[old_len..], .nil);
        self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
    }

    for (0..count) |offset| {
        const array_index = start_index + offset;
        if (array_index > table.array.items.len) continue;
        const value = thread.stack.items[source_start + offset];
        table.array.items[array_index - 1] = value;
        const key = Value{ .integer = @intCast(array_index) };
        if (value != .nil) table.removeHashKey(key);
        self.gc.writeTableBarrier(table, key, value);
    }
    return true;
}

pub const ForValueKind = enum { initial, limit, step };

pub fn forValueName(kind: ForValueKind) []const u8 {
    return switch (kind) {
        .initial => "initial value",
        .limit => "limit",
        .step => "step",
    };
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
        .new_table,
        .set_list,
        .call,
        .tail_call,
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

fn constantString(proto: *const proto_mod.Proto, index: bytecode.ConstantIndex) []const u8 {
    return proto.constants.items[index].string;
}

fn fastTableArrayGet(table_value: Value, key_value: Value) ?Value {
    if (table_value != .table) return null;
    const index = arrayIndex(key_value) orelse return null;
    const table = table_value.table;
    if (index > table.array.items.len) return null;
    const value = table.array.items[index - 1];
    if (value != .nil or index_mod.noIndexMetamethod(table)) return value;
    return null;
}

pub fn assertProtoPrepared(proto: *const proto_mod.Proto) void {
    std.debug.assert(proto.runtime_prepared or proto.constants.items.len == 0);
}

inline fn globalGet(self: *State, proto: *const proto_mod.Proto, name: bytecode.ConstantIndex) Value {
    const table = self.global_table orelse return .nil;
    return table.getStringHashed(constantString(proto, name), proto.constant_hashes[name]);
}

/// Overwrites an existing non-nil global in place, like `State.setGlobal` without interning.
fn fastGlobalSetExisting(self: *State, proto: *const proto_mod.Proto, name: bytecode.ConstantIndex, value: Value) bool {
    if (value == .nil) return false;
    const table = self.global_table orelse return false;
    if (table.rollback) |record| if (!record.header.detached) return false;
    const index = table.findStringEntry(constantString(proto, name), proto.constant_hashes[name]) orelse return false;
    const entry = &table.entries.items[index];
    if (entry.value == .nil) return false;
    entry.value = value;
    self.gc.writeTableBarrier(table, entry.key, value);
    self.gc.markValue(value);
    return true;
}

/// A string's method through its metatable's `__index` table, when that needs no metamethod call.
fn stringMethod(self: *State, name: []const u8, hash: u32) ?Value {
    const metatable = self.string_metatable orelse return null;
    const handler = metatable.metaEvent(.__index);
    if (handler != .table) return null;
    const value = handler.table.getStringHashed(name, hash);
    if (value != .nil or index_mod.noIndexMetamethod(handler.table)) return value;
    return null;
}

fn fastTableFieldGet(table_value: Value, name: []const u8, hash: u32) ?Value {
    if (table_value != .table) return null;
    const table = table_value.table;
    const value = table.getStringHashed(name, hash);
    if (value != .nil) return value;
    const metatable = table.metatable orelse return value;
    if (metatable.metaEventAbsent(.__index)) return value;
    const handler = metatable.metaEvent(.__index);
    if (handler == .nil) return value;
    if (handler != .table) return null;
    const inherited = handler.table.getStringHashed(name, hash);
    if (inherited != .nil or index_mod.noIndexMetamethod(handler.table)) return inherited;
    return null;
}

fn fastTableRawGet(table_value: Value, key_value: Value) ?Value {
    if (fastTableArrayGet(table_value, key_value)) |value| return value;
    // Float keys need normalization to integers first.
    if (table_value != .table or key_value == .number) return null;
    const table = table_value.table;
    const value = table.get(key_value);
    if (value != .nil) return value;
    const metatable = table.metatable orelse return value;
    if (metatable.metaEventAbsent(.__index)) return value;
    const handler = metatable.metaEvent(.__index);
    if (handler == .nil) return value;
    if (handler != .table) return null;
    const inherited = handler.table.get(key_value);
    if (inherited != .nil or index_mod.noIndexMetamethod(handler.table)) return inherited;
    return null;
}

fn fastLengthNoMetamethod(value: Value) ?Value {
    return switch (value) {
        .string => |string| .{ .integer = @intCast(string.len) },
        .table => |table| if (metatable_mod.noMetaEvent(table, .__len)) .{ .integer = table.len() } else null,
        else => null,
    };
}
