const std = @import("std");
const budget_mod = @import("budget.zig");
const compile = @import("../compile.zig");
const stdlib = @import("../stdlib.zig");
const call_mod = @import("call.zig");
const debug_mod = @import("debug.zig");
const failure_mod = @import("failure.zig");
const gc_mod = @import("gc.zig");
const index_mod = @import("index.zig");
const io_mod = @import("io.zig");
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
/// Whether Lua calls and returns jump straight to the next handler; wasm restarts the frame loop.
const direct_frame_dispatch = switch (@import("builtin").cpu.arch) {
    .wasm32, .wasm64 => false,
    else => true,
};
/// Forces inlining outside Debug.
const release_inline: std.builtin.CallModifier = if (std.ascii.eqlIgnoreCase(@tagName(@import("builtin").mode), "debug")) .auto else .always_inline;
const bytecode = compile.bytecode;
const proto_mod = compile.proto;
const lua_max_c_calls = state_mod.lua_max_c_calls;
const Value = types.Value;
const valuesEqual = value_mod.valuesEqual;
const copyValue = types.copyValue;
const loadValue = types.loadValue;
const storeValue = types.storeValue;
const truthy = value_mod.truthy;
const toInteger = value_mod.toInteger;
const toNumber = value_mod.toNumber;
const toNumberMaybe = value_mod.toNumberMaybe;
const arrayIndex = value_mod.arrayIndex;
const appendFmt = value_mod.appendFmt;
const Closure = types.Closure;
const String = types.String;
const Table = types.Table;
const TableEntry = types.TableEntry;
const HashPart = table_index.HashPart;
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
    self.native_stack = self.entryStackGuard();
    self.execution_depth += 1;
    defer self.execution_depth -= 1;
    if (self.execution_depth >= lua_max_c_calls) try call_mod.checkCStack(self, thread);
    if (self.native_stack.exceeded()) try call_mod.failCStackOverflow(self, thread);
    if (thread.rollback != null) try rollback_mod.threadWritable(thread);
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
        const proto = frame.closure.proto;
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

/// Largest vararg copy the fast loop makes.
const fast_vararg_limit = 32;

fn executeInstruction(self: *State, thread: *Thread, proto: *const proto_mod.Proto, instruction: bytecode.Instruction) anyerror!void {
    const frame = &thread.frames.items[thread.frames.items.len - 1];
    const base = frame.base;
    const stack = thread.stack.items;
    switch (instruction) {
        .load_nil => |dest| stack[base + dest] = .nil,
        .load_bool => |op| stack[base + op.dest] = .{ .boolean = op.value },
        .load_const => |op| stack[base + op.dest] = frame.closure.constants()[op.constant],
        .move => |op| stack[base + op.dest] = stack[base + op.source],
        .get_global => |op| stack[base + op.register] = globalGet(self, frame.closure.constants()[op.name].string),
        .set_global => |op| if (!fastGlobalSetExisting(self, frame.closure.constants()[op.name].string, stack[base + op.register])) {
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
                operators_mod.noteStringComparison(self, lhs, rhs);
                stack[base + op.dest] = .{ .boolean = valuesEqual(lhs, rhs) };
            } else {
                try operators_mod.equalValuesToRegister(self, thread, op);
            }
        },
        .lt => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            operators_mod.noteStringComparison(self, lhs, rhs);
            if (operators_mod.rawCompare(lhs, rhs, .lt)) |result| {
                stack[base + op.dest] = .{ .boolean = result };
            } else {
                try operators_mod.compareValuesToRegister(self, thread, op, .lt);
            }
        },
        .le => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            operators_mod.noteStringComparison(self, lhs, rhs);
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
                stack[base + op.dest] = call_mod.namedVarargRead(frame.varargs(thread.stack.items), key_value);
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
            const key = frame.closure.constants()[op.name];
            if (frame.named_vararg_readonly and op.table == proto.param_count) {
                stack[base + op.dest] = call_mod.namedVarargField(frame.varargs(thread.stack.items), key.string.bytes());
            } else if (fastTableFieldGet(table_value, key.string)) |value| {
                stack[base + op.dest] = value;
            } else {
                try index_mod.getTableToRegister(self, thread, op.dest, table_value, key);
            }
        },
        .set_field => |op| try setFieldValue(self, thread, stack[base + op.table], frame.closure.constants()[op.name], stack[base + op.value]),
        .jmp => |offset| try jumpThreadMaybeFast(self, thread, offset, true),
        .compare_branch => |op| {
            const lhs = stack[base + op.left];
            const rhs = stack[base + op.right];
            operators_mod.noteStringComparison(self, lhs, rhs);
            if (operators_mod.rawCompareBranchResult(lhs, rhs, op.branch.op)) |result| {
                if (result == op.branch.jump_if_truthy) try jumpThreadMaybeFast(self, thread, op.branch.offset, true);
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
        .call => |op| try call_mod.callValue(self, thread, op.wide()),
        .tail_call => |op| try call_mod.tailCallValue(self, thread, op.wide()),
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
        inline .add_k, .sub_k, .mul_k, .div_k, .idiv_k, .mod_k, .band_k, .bor_k, .bxor_k, .shl_k, .shr_k => |op, tag| {
            const kind = comptime operators_mod.constantBinaryOp(tag);
            const lhs = stack[base + op.left];
            const rhs = proto.constant_values[op.constant];
            if (operators_mod.rawBinaryOpFast(lhs, rhs, kind)) |value| {
                stack[base + op.dest] = value;
            } else {
                try operators_mod.binaryValuesToRegister(self, thread, op.dest, lhs, rhs, kind);
            }
        },
        .get_method => |op| {
            const table_value = stack[base + op.table];
            const key = frame.closure.constants()[op.name];
            stack[base + op.dest + 1] = table_value;
            if (fastTableFieldGet(table_value, key.string)) |value| {
                stack[base + op.dest] = value;
            } else {
                try index_mod.getTableToRegister(self, thread, op.dest, table_value, key);
            }
        },
        .get_upvalue_field => |op| {
            const table_value = upvalue_mod.readUpvalue(self, thread, op.upvalue);
            const key = frame.closure.constants()[op.name];
            if (fastTableFieldGet(table_value, key.string)) |value| {
                stack[base + op.dest] = value;
            } else {
                try index_mod.getTableToRegister(self, thread, op.dest, table_value, key);
            }
        },
        .set_upvalue_field => |op| try setFieldValue(self, thread, upvalue_mod.readUpvalue(self, thread, op.upvalue), frame.closure.constants()[op.name], stack[base + op.value]),
        .set_field_k => |op| try setFieldValue(self, thread, stack[base + op.table], frame.closure.constants()[op.name], frame.closure.constants()[op.constant]),
        .get_index => |op| {
            const table_value = stack[base + op.table];
            const key: Value = .{ .integer = op.index };
            if (frame.named_vararg_readonly and op.table == proto.param_count) {
                stack[base + op.dest] = call_mod.namedVarargRead(frame.varargs(thread.stack.items), key);
            } else if (fastTableRawGet(table_value, key)) |value| {
                stack[base + op.dest] = value;
            } else {
                try index_mod.getTableToRegister(self, thread, op.dest, table_value, key);
            }
        },
        .set_index => |op| {
            const table_value = stack[base + op.table];
            const key: Value = .{ .integer = op.index };
            const value = stack[base + op.value];
            if (!try fastTableArraySet(self, table_value, key, value)) {
                try index_mod.setTableFromThreadContinuable(self, thread, table_value, key, value);
            }
        },
        .compare_branch_k => |op| {
            const constant = proto.constant_values[op.constant];
            operators_mod.noteStringComparison(self, stack[base + op.register], constant);
            if (operators_mod.rawCompareConstantResult(stack[base + op.register], constant, op.branch.op)) |result| {
                if (result == op.branch.jump_if_truthy) try jumpThreadMaybeFast(self, thread, op.branch.offset, true);
            } else {
                try operators_mod.compareBranchConstant(self, thread, op, constant);
            }
        },
    }
}

fn runPlainFastLoop(self: *State, thread: *Thread, target_frame_count: usize) anyerror!bool {
    if (thread.frames.items.len <= target_frame_count) return false;
    if (self.options.trace_vm) return false;
    if (self.budget.fastLoopInterrupted()) return false;
    if (self.stressPending()) return false;
    if (thread.hook != .nil and (thread.hook_line or thread.hook_count != 0 or thread.hook_running)) return false;
    if (self.gc.running and self.gc.autoStepDue() and self.gc.shouldRunAuto()) return false;
    var budget_allowance = self.budget.fastLoopAllowance();
    if (budget_allowance == 0) return false;

    var stack_limit = @min(thread.stack.items.len, self.stackValueLimit());
    var frame_limit = @min(thread.frames.capacity, self.callFrameLimit());
    var return_floor = @call(.always_inline, fastReturnFloor, .{ thread, target_frame_count });

    var frame_index = thread.frames.items.len - 1;
    var frame = &thread.frames.items[frame_index];
    // Lowered to the executed count while the frame has a line-hook position to forget.
    var allowance = if (hookLineSet(thread, frame_index)) 0 else budget_allowance;
    var proto = frame.closure.proto;
    var pc: usize = frame.pc;
    var base: usize = frame.base;
    // Widen before wrapping subtraction: program counters may be only 32 bits.
    var count_bias: u64 = 0 -% @as(u64, pc);
    // Executed instructions already added to the budget, for Lua that general operations run.
    var flushed: u64 = 0;
    defer self.budget.instructions = self.budget.instructions +| ((pc +% count_bias) -% flushed);
    var segment_start: u64 = 0;
    // Executed-instruction total after a general operation, which may have changed frames.
    var resync: ?u64 = null;
    var instructions: []const bytecode.Instruction = undefined;
    var stack: []Value = undefined;
    frames: while (true) {
        if (resync) |executed| {
            @branchHint(.unlikely);
            resync = null;
            flushed = flushExecuted(self, executed, flushed);
            const resumed = try fastLoopResume(self, thread, target_frame_count) orelse {
                pc = 0;
                count_bias = flushed;
                return true;
            };
            budget_allowance = flushed +| resumed.allowance;
            frame_index = thread.frames.items.len - 1;
            frame = &thread.frames.items[frame_index];
            proto = frame.closure.proto;
            pc = frame.pc;
            count_bias = executed -% pc;
            if (executed >= budget_allowance) return true;
            allowance = if (hookLineSet(thread, frame_index)) executed else budget_allowance;
            base = frame.base;
            stack_limit = @min(thread.stack.items.len, self.stackValueLimit());
            frame_limit = @min(thread.frames.capacity, self.callFrameLimit());
            return_floor = resumed.return_floor;
        }
        if (!proto.fast_loop_entry) return segment_start != 0;
        instructions = proto.instructions.items;
        if (pc >= instructions.len) return segment_start != 0;
        stack = thread.stack.items[base..];

        // Per-opcode dispatch on the tag only; handlers decode operands so the union is never copied.
        fast_loop: switch (std.meta.activeTag(instructions[pc])) {
            .load_nil => {
                const dest = instructions[pc].load_nil;
                storeValue(&stack[dest], .nil);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .load_bool => {
                const op = instructions[pc].load_bool;
                storeValue(&stack[op.dest], .{ .boolean = op.value });
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .load_const => {
                const op = instructions[pc].load_const;
                const decoded = proto.constant_values[op.constant];
                storeValue(&stack[op.dest], if (decoded != .string) decoded else frame.closure.constants()[op.constant]);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .move => {
                const op = instructions[pc].move;
                copyValue(&stack[op.dest], &stack[op.source]);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .get_upvalue => {
                const op = instructions[pc].get_upvalue;
                copyValue(&stack[op.register], frame.closure.upvalues()[op.upvalue].value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_upvalue => {
                const op = instructions[pc].set_upvalue;
                const upvalue = frame.closure.upvalues()[op.upvalue];
                const value = loadValue(&stack[op.register]);
                switch (upvalue.cell) {
                    .open => |slot| {
                        if (slot.owner != thread and !foreignUpvalueWritable(self, slot.owner)) break :fast_loop;
                        copyValue(upvalue.value, &stack[op.register]);
                    },
                    .closed => {
                        rollback_mod.touch(upvalue);
                        storeValue(upvalue.value, value);
                        self.gc.writeBarrier(upvalue, value);
                    },
                }
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .add => {
                const op = instructions[pc].add;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .add })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .sub => {
                const op = instructions[pc].sub;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .sub })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .mul => {
                const op = instructions[pc].mul;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .mul })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .div => {
                const op = instructions[pc].div;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .div })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .idiv => {
                const op = instructions[pc].idiv;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .idiv })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .mod => {
                const op = instructions[pc].mod;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .mod })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .band => {
                const op = instructions[pc].band;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .band })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .bor => {
                const op = instructions[pc].bor;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .bor })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .bxor => {
                const op = instructions[pc].bxor;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .bxor })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .shl => {
                const op = instructions[pc].shl;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .shl })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .shr => {
                const op = instructions[pc].shr;
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &stack[op.right], .shr })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .eq => {
                const op = instructions[pc].eq;
                const lhs = loadValue(&stack[op.left]);
                const rhs = loadValue(&stack[op.right]);
                if (operators_mod.comparesLongStrings(lhs, rhs)) break :fast_loop;
                if (operators_mod.equalityHasMetamethod(lhs, rhs) and !valuesEqual(lhs, rhs)) break :fast_loop;
                storeValue(&stack[op.dest], .{ .boolean = valuesEqual(lhs, rhs) });
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .lt => {
                const op = instructions[pc].lt;
                if (operators_mod.comparesLongStrings(loadValue(&stack[op.left]), loadValue(&stack[op.right]))) break :fast_loop;
                const result = operators_mod.rawCompare(loadValue(&stack[op.left]), loadValue(&stack[op.right]), .lt) orelse break :fast_loop;
                storeValue(&stack[op.dest], .{ .boolean = result });
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .le => {
                const op = instructions[pc].le;
                if (operators_mod.comparesLongStrings(loadValue(&stack[op.left]), loadValue(&stack[op.right]))) break :fast_loop;
                const result = operators_mod.rawCompare(loadValue(&stack[op.left]), loadValue(&stack[op.right]), .le) orelse break :fast_loop;
                storeValue(&stack[op.dest], .{ .boolean = result });
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .not => {
                const op = instructions[pc].not;
                const result = !truthy(loadValue(&stack[op.source]));
                storeValue(&stack[op.dest], .{ .boolean = result });
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .unm => {
                const op = instructions[pc].unm;
                stack[op.dest] = switch (loadValue(&stack[op.source])) {
                    .integer => |value| .{ .integer = -%value },
                    .number => |value| .{ .number = -value },
                    else => break :fast_loop,
                };
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .bnot => {
                const op = instructions[pc].bnot;
                const value = loadValue(&stack[op.source]);
                if (value != .integer) break :fast_loop;
                storeValue(&stack[op.dest], .{ .integer = ~value.integer });
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .len => {
                const op = instructions[pc].len;
                const value = fastLengthNoMetamethod(loadValue(&stack[op.source])) orelse break :fast_loop;
                storeValue(&stack[op.dest], value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .get_table => {
                const op = instructions[pc].get_table;
                const table_value = loadValue(&stack[op.table]);
                const key = loadValue(&stack[op.key]);
                const value = if (frame.named_vararg_readonly and op.table == proto.param_count)
                    call_mod.namedVarargRead(frame.varargs(thread.stack.items), key)
                else if (arrayValue(table_value, key)) |hit|
                    hit
                else
                    fastTableRawGet(table_value, key) orelse break :fast_loop;
                storeValue(&stack[op.dest], value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .get_field => {
                const op = instructions[pc].get_field;
                const key = frame.closure.constants()[op.name].string;
                const named_vararg = frame.named_vararg_readonly and op.table == proto.param_count;
                if (!named_vararg) if (fieldValue(loadValue(&stack[op.table]), key)) |hit| {
                    copyValue(&stack[op.dest], hit);
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                };
                const value = if (named_vararg)
                    call_mod.namedVarargField(frame.varargs(thread.stack.items), key.bytes())
                else if (loadValue(&stack[op.table]) == .string)
                    stringMethod(self, key) orelse break :fast_loop
                else if (loadValue(&stack[op.table]) == .userdata)
                    userdataField(stack[op.table].userdata, key) orelse break :fast_loop
                else
                    fastTableFieldGet(loadValue(&stack[op.table]), key) orelse break :fast_loop;
                storeValue(&stack[op.dest], value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_table => {
                const op = instructions[pc].set_table;
                if (arraySlot(loadValue(&stack[op.table]), loadValue(&stack[op.key]))) |slot| {
                    const table = stack[op.table].table;
                    slot.* = loadValue(&stack[op.value]);
                    self.gc.writeTableBarrier(table, loadValue(&stack[op.key]), loadValue(&stack[op.value]));
                    pc += 1;
                    continue :fast_loop std.meta.activeTag(instructions[pc]);
                }
                if (!fastTableArraySetExistingNoAlloc(self, loadValue(&stack[op.table]), loadValue(&stack[op.key]), loadValue(&stack[op.value])) and
                    !fastTableDynamicKeySetNoAlloc(self, loadValue(&stack[op.table]), loadValue(&stack[op.key]), loadValue(&stack[op.value]))) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_array => {
                const op = instructions[pc].set_array;
                const table_value = loadValue(&stack[op.table]);
                if (table_value != .table or op.index == 0) break :fast_loop;
                const table = table_value.table;
                if (table.rollback) |record| if (!record.header.detached) break :fast_loop;
                const index: usize = op.index;
                const value = loadValue(&stack[op.value]);
                if (index <= table.array.len) {
                    table.array.items()[index - 1] = value;
                } else if (value != .nil) {
                    if (index > table.array.capacity) break :fast_loop;
                    table.extendArrayAssumeCapacity(index);
                    table.array.items()[index - 1] = value;
                }
                self.gc.writeTableBarrier(table, .{ .integer = @intCast(index) }, value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_field => {
                const op = instructions[pc].set_field;
                if (!fastFieldStore(self, loadValue(&stack[op.table]), frame.closure.constants()[op.name], loadValue(&stack[op.value]))) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .get_method => {
                const op = instructions[pc].get_method;
                const table_value = loadValue(&stack[op.table]);
                const key = frame.closure.constants()[op.name].string;
                const value = if (fieldValue(table_value, key)) |hit|
                    hit.*
                else if (table_value == .string)
                    stringMethod(self, key) orelse break :fast_loop
                else if (table_value == .userdata)
                    userdataField(table_value.userdata, key) orelse break :fast_loop
                else
                    fastTableFieldGet(table_value, key) orelse break :fast_loop;
                storeValue(&stack[op.dest + 1], table_value);
                storeValue(&stack[op.dest], value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .get_upvalue_field => {
                const op = instructions[pc].get_upvalue_field;
                const table_value = frame.closure.upvalues()[op.upvalue].get();
                const key = frame.closure.constants()[op.name].string;
                const value = if (fieldValue(table_value, key)) |hit| hit.* else fastTableFieldGet(table_value, key) orelse break :fast_loop;
                storeValue(&stack[op.dest], value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_upvalue_field => {
                const op = instructions[pc].set_upvalue_field;
                const table_value = frame.closure.upvalues()[op.upvalue].get();
                if (!fastFieldStore(self, table_value, frame.closure.constants()[op.name], loadValue(&stack[op.value]))) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_field_k => {
                const op = instructions[pc].set_field_k;
                const decoded = proto.constant_values[op.constant];
                const value = if (decoded != .string) decoded else frame.closure.constants()[op.constant];
                if (!fastFieldStore(self, loadValue(&stack[op.table]), frame.closure.constants()[op.name], value)) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .get_index => {
                const op = instructions[pc].get_index;
                const table_value = loadValue(&stack[op.table]);
                const key: Value = .{ .integer = op.index };
                const value = if (frame.named_vararg_readonly and op.table == proto.param_count)
                    call_mod.namedVarargRead(frame.varargs(thread.stack.items), key)
                else if (arrayValue(table_value, key)) |hit|
                    hit
                else
                    fastTableRawGet(table_value, key) orelse break :fast_loop;
                storeValue(&stack[op.dest], value);
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_index => {
                const op = instructions[pc].set_index;
                const table_value = loadValue(&stack[op.table]);
                const key: Value = .{ .integer = op.index };
                const value = loadValue(&stack[op.value]);
                if (arraySlot(table_value, key)) |slot| {
                    slot.* = value;
                    self.gc.writeTableBarrier(table_value.table, key, value);
                } else if (!fastTableArraySetExistingNoAlloc(self, table_value, key, value)) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            inline .add_k, .sub_k, .mul_k, .div_k, .idiv_k, .mod_k, .band_k, .bor_k, .bxor_k, .shl_k, .shr_k => |tag| {
                const op = @field(instructions[pc], @tagName(tag));
                const kind = comptime operators_mod.constantBinaryOp(tag);
                if (!@call(release_inline, operators_mod.binarySlotOpFast, .{ &stack[op.dest], &stack[op.left], &proto.constant_values[op.constant], kind })) break :fast_loop;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .compare_branch_k => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const op = instructions[pc].compare_branch_k;
                const value = loadValue(&stack[op.register]);
                const constant = proto.constant_values[op.constant];
                if (operators_mod.comparesLongStrings(value, constant)) break :fast_loop;
                const result = if (value == .integer and constant == .integer) switch (op.branch.op) {
                    .eq => value.integer == constant.integer,
                    .lt => value.integer < constant.integer,
                    .le => value.integer <= constant.integer,
                    .gt => value.integer > constant.integer,
                    .ge => value.integer >= constant.integer,
                } else operators_mod.rawCompareConstantResult(value, constant, op.branch.op) orelse break :fast_loop;
                pc += 1;
                if (result == op.branch.jump_if_truthy) {
                    const source_pc = pc;
                    pc = jumpTarget(source_pc, op.branch.offset);
                    count_bias +%= @as(u64, source_pc) -% @as(u64, pc);
                    if (pc < source_pc) {
                        if (pc +% count_bias >= allowance) {
                            allowance = backwardJumpAllowance(thread, frame_index, budget_allowance);
                            if (pc +% count_bias >= allowance) break :fast_loop;
                        }
                    }
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .compare_branch => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const op = instructions[pc].compare_branch;
                const lhs = loadValue(&stack[op.left]);
                const rhs = loadValue(&stack[op.right]);
                if (operators_mod.comparesLongStrings(lhs, rhs)) break :fast_loop;
                const result = if (lhs == .integer and rhs == .integer) switch (op.branch.op) {
                    .eq => lhs.integer == rhs.integer,
                    .lt => lhs.integer < rhs.integer,
                    .le => lhs.integer <= rhs.integer,
                } else operators_mod.rawCompareBranchResult(lhs, rhs, op.branch.op) orelse break :fast_loop;
                pc += 1;
                if (result == op.branch.jump_if_truthy) {
                    const source_pc = pc;
                    pc = jumpTarget(source_pc, op.branch.offset);
                    count_bias +%= @as(u64, source_pc) -% @as(u64, pc);
                    if (pc < source_pc) {
                        if (pc +% count_bias >= allowance) {
                            allowance = backwardJumpAllowance(thread, frame_index, budget_allowance);
                            if (pc +% count_bias >= allowance) break :fast_loop;
                        }
                    }
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .jmp => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const offset = instructions[pc].jmp;
                pc += 1;
                const source_pc = pc;
                pc = jumpTarget(source_pc, offset);
                count_bias +%= @as(u64, source_pc) -% @as(u64, pc);
                if (pc < source_pc) {
                    if (pc +% count_bias >= allowance) {
                        allowance = backwardJumpAllowance(thread, frame_index, budget_allowance);
                        if (pc +% count_bias >= allowance) break :fast_loop;
                    }
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .test_op => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const op = instructions[pc].test_op;
                pc += 1;
                if (truthy(loadValue(&stack[op.register])) == op.jump_if_truthy) {
                    const source_pc = pc;
                    pc = jumpTarget(source_pc, op.offset);
                    count_bias +%= @as(u64, source_pc) -% @as(u64, pc);
                    if (pc < source_pc) {
                        if (pc +% count_bias >= allowance) {
                            allowance = backwardJumpAllowance(thread, frame_index, budget_allowance);
                            if (pc +% count_bias >= allowance) break :fast_loop;
                        }
                    }
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .test_set => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const op = instructions[pc].test_set;
                const value = loadValue(&stack[op.source]);
                storeValue(&stack[op.dest], value);
                pc += 1;
                if (truthy(value) == op.jump_if_truthy) {
                    const source_pc = pc;
                    pc = jumpTarget(source_pc, op.offset);
                    count_bias +%= @as(u64, source_pc) -% @as(u64, pc);
                    if (pc < source_pc) {
                        if (pc +% count_bias >= allowance) {
                            allowance = backwardJumpAllowance(thread, frame_index, budget_allowance);
                            if (pc +% count_bias >= allowance) break :fast_loop;
                        }
                    }
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .for_prep => {
                const op = instructions[pc].for_prep;
                const loop = stack[op.base..][0..3];
                if (loop[0] != .integer or loop[1] != .integer or loop[2] != .integer or loop[2].integer == 0) break :fast_loop;
                pc += 1;
                if (integerForCount(loop[0].integer, loop[1].integer, loop[2].integer)) |count| {
                    loop[1].integer = @bitCast(count);
                } else {
                    const source_pc = pc;
                    pc = jumpTarget(source_pc, op.offset);
                    count_bias +%= @as(u64, source_pc) -% @as(u64, pc);
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .for_loop => {
                const op = instructions[pc].for_loop;
                const loop = stack[op.base..][0..3];
                pc += 1;
                if (loop[0] == .integer and loop[1] == .integer and loop[2] == .integer) {
                    const count: u64 = @bitCast(loop[1].integer);
                    if (count == 0) continue :fast_loop std.meta.activeTag(instructions[pc]);
                    loop[1].integer = @bitCast(count - 1);
                    loop[0].integer +%= loop[2].integer;
                } else if (loop[0] == .number and loop[1] == .number and loop[2] == .number) {
                    const next = loop[0].number + loop[2].number;
                    loop[0].number = next;
                    if (!forLoopContinuesNumber(next, loop[1].number, loop[2].number)) continue :fast_loop std.meta.activeTag(instructions[pc]);
                } else {
                    pc -= 1;
                    break :fast_loop;
                }
                const source_pc = pc;
                pc = jumpTarget(source_pc, op.offset);
                count_bias +%= @as(u64, source_pc) -% @as(u64, pc);
                if (pc +% count_bias >= allowance) {
                    allowance = backwardJumpAllowance(thread, frame_index, budget_allowance);
                    if (pc +% count_bias >= allowance) break :fast_loop;
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .call => {
                var op = instructions[pc].call.wide();
                if (thread.hook_call) break :fast_loop;
                if (op.arg_count == bytecode.multret_arg_count) {
                    // Only valid while a preceding call/vararg still owns the last-result state.
                    if (pc +% count_bias != segment_start) break :fast_loop;
                    const expected_base = base + op.base + 1;
                    if (thread.last_result_base < expected_base) break :fast_loop;
                    const result_end = thread.last_result_base + thread.last_result_count;
                    op.arg_count = @intCast(result_end -| expected_base);
                }
                const callee = loadValue(&stack[op.base]);
                if (callee == .native and stdlib.math.hasFastUnaryResult(callee.native) and !thread.hook_return and op.arg_count != 0 and @as(usize, op.base) + 1 < stack.len) math: {
                    const result = stdlib.math.fastUnaryResult(callee.native, loadValue(&stack[op.base + 1])) orelse break :math;
                    const return_count: usize = if (op.return_count == bytecode.multret_count) 1 else op.return_count;
                    const absolute_base = base + op.base;
                    const stored_end = absolute_base + @max(return_count, 1);
                    if (stored_end > stack_limit) break :math;
                    storeValue(&stack[op.base], result);
                    if (return_count > 1) @memset(thread.stack.items[absolute_base + 1 .. stored_end], .nil);
                    thread.last_result_base = absolute_base;
                    thread.last_result_count = return_count;
                    thread.last_transfer_base = absolute_base;
                    thread.last_transfer_count = 1;
                    thread.next_call_name = null;
                    thread.next_call_namewhat = null;
                    pc += 1;
                    frame.pc = @intCast(pc);
                    segment_start = pc +% count_bias;
                    continue :frames;
                }
                if (callee != .closure or !callee.closure.proto.fast_loop_call or thread.next_call_name != null or thread.next_call_namewhat != null) {
                    // Natives and frames needing setup run through the general call path in place.
                    @branchHint(.unlikely);
                    if (thread.hook != .nil) break :fast_loop;
                    if (pc +% count_bias != segment_start) {
                        thread.last_result_count = 0;
                        thread.last_transfer_count = 0;
                    }
                    pc += 1;
                    frame.pc = @intCast(pc);
                    segment_start = pc +% count_bias;
                    flushed = flushExecuted(self, segment_start, flushed);
                    if (callee == .closure) {
                        try call_mod.callValue(self, thread, op);
                    } else if (value_mod.isNativeCallable(callee) and thread.next_call_name == null and thread.next_call_namewhat == null) {
                        try call_mod.invokeNative(self, thread, op, callee);
                        if (thread.frames.items.len == frame_index + 1 and nativeLeftFastLoopIntact(self, thread)) intact: {
                            const fresh_allowance = flushed +| @call(.always_inline, budget_mod.Budget.fastLoopAllowance, .{&self.budget});
                            if (segment_start >= fresh_allowance or hookLineSet(thread, frame_index)) break :intact;
                            budget_allowance = fresh_allowance;
                            allowance = fresh_allowance;
                            return_floor = @call(.always_inline, fastReturnFloor, .{ thread, target_frame_count });
                            frame = &thread.frames.items[frame_index];
                            stack_limit = @min(thread.stack.items.len, self.stackValueLimit());
                            frame_limit = @min(thread.frames.capacity, self.callFrameLimit());
                            stack = thread.stack.items[base..];
                            continue :fast_loop std.meta.activeTag(instructions[pc]);
                        }
                    } else {
                        try call_mod.invokeValue(self, thread, op, 0);
                    }
                    resync = segment_start;
                    continue :frames;
                }
                const closure = callee.closure;
                const callee_proto = closure.proto;
                const callee_index = frame_index + 1;
                if (callee_index >= frame_limit) break :fast_loop;
                const function_slot = base + op.base;
                const argument_base = function_slot + 1;
                const param_count = callee_proto.param_count;
                var callee_base = argument_base;
                var vararg_count: u32 = 0;
                if (callee_proto.is_vararg and op.arg_count > param_count) {
                    @branchHint(.unlikely);
                    vararg_count = op.arg_count - param_count;
                    callee_base += op.arg_count;
                    if (callee_base + callee_proto.max_registers > stack_limit) break :fast_loop;
                    shiftParameters(thread.stack.items, argument_base, callee_base, param_count);
                }
                const register_count = @max(callee_proto.max_registers, 1);
                const stack_end = callee_base + register_count;
                if (stack_end > stack_limit) break :fast_loop;

                const executed_count = pc +% count_bias -% segment_start;
                const copied = @min(op.arg_count, param_count);
                const cleared_end = param_count + @intFromBool(callee_proto.named_vararg_readonly);
                if (copied < cleared_end) clearRegisters(thread.stack.items[callee_base + copied .. callee_base + cleared_end]);
                frame.pc = @intCast(pc + 1);
                frame = &@as([*]CallFrame, @ptrCast(frame))[1];
                frame.* = .{
                    .closure = closure,
                    .base = @intCast(callee_base),
                    .pc = 0,
                    .return_start = @intCast(function_slot),
                    .return_count = op.return_count,
                    .vararg_base = @intCast(argument_base + param_count),
                    .vararg_count = vararg_count,
                    .named_vararg_readonly = callee_proto.named_vararg_readonly,
                };
                thread.frames.items.len = callee_index + 1;
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
                if (pc +% count_bias >= allowance) return true;
                if (!direct_frame_dispatch) continue :frames;
                instructions = proto.instructions.items;
                stack = thread.stack.items[base..];
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .vararg => {
                const op = instructions[pc].vararg;
                if (proto.named_vararg and !frame.named_vararg_readonly) break :fast_loop;
                const available = frame.vararg_count;
                const count: usize = if (op.count == bytecode.multret_count) available else op.count;
                if (count > fast_vararg_limit or base + op.dest + count > stack_limit) break :fast_loop;
                const copied = @min(count, available);
                for (0..copied) |index| copyValue(&stack[op.dest + index], &thread.stack.items[frame.vararg_base + index]);
                clearRegisters(stack[op.dest + copied .. op.dest + count]);
                pc += 1;
                if (op.count == bytecode.multret_count) {
                    thread.last_result_base = base + op.dest;
                    thread.last_result_count = count;
                    frame.pc = @intCast(pc);
                    segment_start = pc +% count_bias;
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .new_table => {
                const op = instructions[pc].new_table;
                pc += 1;
                frame.pc = @intCast(pc);
                storeValue(&stack[op.dest], try self.newTableWithHints(op.array_hint, op.hash_hint));
                if (self.gc.running and self.gc.autoStepDue()) {
                    resync = pc +% count_bias;
                    continue :frames;
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .closure => {
                const op = instructions[pc].closure;
                pc += 1;
                frame.pc = @intCast(pc);
                storeValue(&stack[op.dest], try self.newClosure(thread, proto.children.items[op.proto]));
                if (self.gc.running and self.gc.autoStepDue()) {
                    resync = pc +% count_bias;
                    continue :frames;
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .set_list => {
                const op = instructions[pc].set_list;
                if (op.count == bytecode.set_list_multret and pc +% count_bias != segment_start) break :fast_loop;
                pc += 1;
                frame.pc = @intCast(pc);
                try setList(self, thread, op);
                resync = pc +% count_bias;
                continue :frames;
            },
            .tail_call => {
                const op = instructions[pc].tail_call.wide();
                if (thread.hook != .nil) break :fast_loop;
                lua_tail: {
                    var arg_count = op.arg_count;
                    if (arg_count == bytecode.multret_arg_count) {
                        if (pc +% count_bias != segment_start) break :lua_tail;
                        const expected_base = base + op.base + 1;
                        if (thread.last_result_base < expected_base) break :lua_tail;
                        arg_count = @intCast((thread.last_result_base + thread.last_result_count) -| expected_base);
                    }
                    const callee = loadValue(&stack[op.base]);
                    if (callee != .closure or !callee.closure.proto.fast_loop_call or proto.has_to_close_locals or frame.has_extra or
                        thread.next_call_name != null or thread.next_call_namewhat != null) break :lua_tail;
                    const closure = callee.closure;
                    const callee_proto = closure.proto;
                    const param_count = callee_proto.param_count;
                    const argument_base = frame.argumentBase();
                    const vararg_count: u32 = if (callee_proto.is_vararg and arg_count > param_count) arg_count - param_count else 0;
                    const callee_base = if (vararg_count != 0) argument_base + arg_count else argument_base;
                    if (callee_base + @max(callee_proto.max_registers, 1) > stack_limit) break :lua_tail;

                    if (thread.open_upvalues) |upvalue| if (upvalue.cell.open.stack_index >= base) upvalue_mod.closeUpvalues(self, thread, base);
                    const source = base + op.base + 1;
                    const copied = @min(arg_count, param_count);
                    const moved = if (vararg_count != 0) arg_count else copied;
                    for (0..moved) |index| copyValue(&thread.stack.items[argument_base + index], &thread.stack.items[source + index]);
                    if (vararg_count != 0) shiftParameters(thread.stack.items, argument_base, callee_base, param_count);
                    const cleared_end = param_count + @intFromBool(callee_proto.named_vararg_readonly);
                    if (copied < cleared_end) clearRegisters(thread.stack.items[callee_base + copied .. callee_base + cleared_end]);

                    const executed_count = pc +% count_bias -% segment_start;
                    frame.* = .{
                        .closure = closure,
                        .base = @intCast(callee_base),
                        .pc = 0,
                        .return_start = frame.return_start,
                        .return_count = frame.return_count,
                        .vararg_base = @intCast(argument_base + param_count),
                        .vararg_count = vararg_count,
                        .named_vararg_readonly = callee_proto.named_vararg_readonly,
                        .is_tail_call = true,
                    };
                    if (executed_count != 0) {
                        thread.last_result_count = 0;
                        thread.last_transfer_count = 0;
                    }
                    proto = callee_proto;
                    segment_start = pc +% count_bias +% 1;
                    count_bias = segment_start;
                    pc = 0;
                    base = callee_base;
                    if (pc +% count_bias >= allowance) return true;
                    continue :frames;
                }
                if (pc +% count_bias != segment_start) {
                    if (op.arg_count == bytecode.multret_arg_count) break :fast_loop;
                    thread.last_result_count = 0;
                    thread.last_transfer_count = 0;
                }
                pc += 1;
                frame.pc = @intCast(pc);
                segment_start = pc +% count_bias;
                flushed = flushExecuted(self, segment_start, flushed);
                try call_mod.tailCallValue(self, thread, op);
                resync = segment_start;
                continue :frames;
            },
            .ret => {
                const op = instructions[pc].ret;
                // Returning onto the floor frame is fine, but the outer loop must take over afterwards.
                if (frame_index < return_floor or frame_index == 0) break :fast_loop;
                if (proto.has_to_close_locals or op.count == bytecode.multret_count or
                    (frame.has_extra and thread.frame_extras.items[frame_index].pending_returns != null))
                {
                    @branchHint(.unlikely);
                    if (thread.hook != .nil) break :fast_loop;
                    if (pc +% count_bias != segment_start) {
                        thread.last_result_count = 0;
                        thread.last_transfer_count = 0;
                    }
                    pc += 1;
                    frame.pc = @intCast(pc);
                    segment_start = pc +% count_bias;
                    flushed = flushExecuted(self, segment_start, flushed);
                    try call_mod.returnFromFrame(self, thread, op.first, op.count);
                    resync = segment_start;
                    continue :frames;
                }
                const return_start = frame.return_start;
                const return_count: u32 = if (frame.return_count == bytecode.multret_count) op.count else frame.return_count;
                if (return_start + return_count > stack_limit) break :fast_loop;
                if (thread.open_upvalues) |upvalue| if (upvalue.cell.open.stack_index >= base) upvalue_mod.closeUpvalues(self, thread, base);
                const executed_count = pc +% count_bias -% segment_start;
                const copied = @min(return_count, op.count);
                if (copied == 1 and return_count == 1) {
                    copyValue(&(stack.ptr - base)[return_start], &stack[op.first]);
                } else {
                    for (0..copied) |index| copyValue(&thread.stack.items[return_start + index], &stack[op.first + index]);
                    clearRegisters(thread.stack.items[return_start + copied .. return_start + return_count]);
                }
                thread.frames.items.len = frame_index;
                thread.last_result_base = return_start;
                thread.last_result_count = return_count;
                if (executed_count != 0) thread.last_transfer_count = 0;
                segment_start = pc +% count_bias +% 1;
                frame_index -= 1;
                frame = &(@as([*]CallFrame, @ptrCast(frame)) - 1)[0];
                proto = frame.closure.proto;
                pc = frame.pc;
                count_bias = segment_start -% pc;
                base = frame.base;
                if (frame_index + 1 == return_floor or pc +% count_bias >= allowance) return true;
                if (hookLineSet(thread, frame_index)) allowance = pc +% count_bias;
                if (!direct_frame_dispatch or !proto.fast_loop_entry) continue :frames;
                instructions = proto.instructions.items;
                stack = thread.stack.items[base..];
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .tfor_prep => {
                const op = instructions[pc].tfor_prep;
                const pair = fastGenericForStep(loadValue(&stack[op.base]), loadValue(&stack[op.base + 1]), loadValue(&stack[op.base + 2])) orelse break :fast_loop;
                storeValue(&stack[op.base + 2], pair[0]);
                for (0..op.variable_count) |index| stack[op.base + 4 + index] = if (index < pair.len) pair[index] else .nil;
                pc += 1;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .tfor_loop => {
                if (proto.jumpExitsToBeClosed(pc)) break :fast_loop;
                const op = instructions[pc].tfor_loop;
                pc += 1;
                const source_pc = pc;
                pc = jumpTarget(source_pc, op.offset);
                count_bias +%= @as(u64, source_pc) -% @as(u64, pc);
                if (pc < source_pc) {
                    if (pc +% count_bias >= allowance) {
                        allowance = backwardJumpAllowance(thread, frame_index, budget_allowance);
                        if (pc +% count_bias >= allowance) break :fast_loop;
                    }
                }
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .close => {
                const first = base + instructions[pc].close;
                if (thread.open_upvalues) |upvalue| if (upvalue.cell.open.stack_index >= first) upvalue_mod.closeUpvalues(self, thread, first);
                pc += 1;
                if (pc >= instructions.len) break :fast_loop;
                continue :fast_loop std.meta.activeTag(instructions[pc]);
            },
            .get_global, .set_global, .declare_global, .pow, .concat, .check_close, .close_tbc, .tfor_call, .concat_range => break :fast_loop,
        }

        if (pc +% count_bias == segment_start) return segment_start != 0;
        frame.pc = @intCast(pc);
        thread.last_result_count = 0;
        thread.last_transfer_count = 0;
        return true;
    }
}

/// Null when the loop ends or needs the general path.
inline fn fastGenericForStep(iterator: Value, state: Value, control: Value) ?[2]Value {
    if (state != .table) return null;
    const table = state.table;
    const pair: [2]Value = switch (iterator) {
        .native_next => if (control == .number) return null else table.next(control) catch return null,
        .native_ipairs_iter => pair: {
            if (control != .integer) return null;
            const next_index = control.integer +% 1;
            break :pair .{ .{ .integer = next_index }, table.get(.{ .integer = next_index }) };
        },
        else => return null,
    };
    if (pair[0] == .nil or pair[1] == .nil) return null;
    return pair;
}

/// Small frames clear their registers inline; a `memset` call costs more than the stores.
noinline fn shiftParameters(stack: []Value, source: usize, dest: usize, count: usize) void {
    for (0..count) |index| copyValue(&stack[dest + index], &stack[source + index]);
}

inline fn clearRegisters(registers: []Value) void {
    if (registers.len > 16) return @memset(registers, .nil);
    for (registers) |*register| register.* = .nil;
}

inline fn arrayValue(table_value: Value, key: Value) ?Value {
    if (table_value != .table or key != .integer) return null;
    const table = table_value.table;
    const index: u64 = @bitCast(key.integer -% 1);
    if (index >= table.array.len) return null;
    const value = loadValue(&table.array.items()[@intCast(index)]);
    return if (value != .nil) value else null;
}

/// Slot of an existing non-nil array element that a raw write may replace.
inline fn arraySlot(table_value: Value, key: Value) ?*Value {
    if (table_value != .table or key != .integer) return null;
    const table = table_value.table;
    const index: u64 = @bitCast(key.integer -% 1);
    if (index >= table.array.len) return null;
    if (table.rollback) |record| if (!record.header.detached) return null;
    const slot = &table.array.items()[@intCast(index)];
    return if (slot.* != .nil) slot else null;
}

inline fn fieldEntry(part: *const HashPart, key: *const String) ?*TableEntry {
    const entries = part.entries();
    if (key.field_hint < entries.len) {
        const entry = &entries[key.field_hint];
        if (entry.key == .string and entry.key.string == key) return entry;
    }
    if (!key.isShort()) return null;
    const index = part.find(.{ .string = key }) orelse return null;
    if (index < String.no_field_hint and !key.static) @constCast(key).field_hint = @intCast(index);
    return &entries[index];
}

/// Non-nil value of `key` in the table's own hash part.
inline fn fieldValue(table_value: Value, key: *const String) ?*const Value {
    if (table_value != .table) return null;
    const part = table_value.table.hash orelse return null;
    const slot = &(fieldEntry(part, key) orelse return null).value;
    return if (slot.* != .nil) slot else null;
}

/// Stores `value` at string `key` without metamethods or allocation, or returns false.
inline fn fastFieldStore(self: *State, table_value: Value, key: Value, value: Value) bool {
    if (fieldSlot(table_value, key.string)) |slot| {
        slot.* = value;
        self.gc.writeExistingKeyBarrier(table_value.table, key, value);
        return true;
    }
    return fastTableKnownKeySetExistingNoAlloc(self, table_value, key, value);
}

/// Slot of an existing non-nil string-keyed hash entry that a raw write may replace.
inline fn fieldSlot(table_value: Value, key: *const String) ?*Value {
    if (table_value != .table) return null;
    const table = table_value.table;
    if (table.rollback) |record| if (!record.header.detached) return null;
    const part = table.hash orelse return null;
    const slot = &(fieldEntry(part, key) orelse return null).value;
    return if (slot.* != .nil) slot else null;
}

/// Prepares a write to an open upvalue on another thread's stack; false when that stack
/// must first be copied for rollback.
noinline fn foreignUpvalueWritable(self: *State, owner: *Thread) bool {
    if (owner.rollback) |record| if (!record.header.detached) return false;
    self.gc.rememberObject(.{ .thread = owner });
    return true;
}

/// True when the frame at `index` has a line-hook position that a backward jump must forget.
inline fn hookLineSet(thread: *const Thread, index: usize) bool {
    return thread.frames.items[index].has_extra and thread.frame_extras.items[index].last_hook_line != null;
}

/// Forgets the line-hook position of the frame at `index` after a backward jump and
/// returns the allowance to continue with.
noinline fn backwardJumpAllowance(thread: *Thread, index: usize, budget_allowance: u64) u64 {
    @branchHint(.cold);
    if (hookLineSet(thread, index)) thread.frame_extras.items[index].last_hook_line = null;
    return budget_allowance;
}

fn fastReturnFloor(thread: *const Thread, target_frame_count: usize) usize {
    if (thread.pending_unwind_error != null or thread.pending_yield_hook_return or thread.hook_return) return std.math.maxInt(usize);
    if (call_mod.hasPendingContinuations(thread)) return @max(target_frame_count, thread.continuation_frame_count);
    return target_frame_count;
}

/// Adds the instructions executed since the last flush to the budget; returns the new flush point.
inline fn flushExecuted(self: *State, executed: u64, flushed: u64) u64 {
    self.budget.instructions = self.budget.instructions +| (executed -% flushed);
    return executed;
}

/// Whether a native that returned to the frame it was called from left nothing for
/// `fastLoopResume` to act on.
inline fn nativeLeftFastLoopIntact(self: *State, thread: *Thread) bool {
    if (self.gc.running and self.gc.autoStepDue()) return false;
    if (self.stressPending() or self.budget.interruptRequested()) return false;
    if (thread.hook != .nil or thread.pending_unwind_error != null or thread.pending_yield_hook_return) return false;
    return !call_mod.hasPendingContinuations(thread) or thread.frames.items.len > thread.continuation_frame_count;
}

const FastLoopResume = struct {
    /// `Budget.fastLoopAllowance` for the instructions to come.
    allowance: u64,
    return_floor: usize,
};

/// After a general operation from the fast loop: runs a due collector step, then returns
/// what the fast loop continues the thread's new top frame with, or null if it may not.
noinline fn fastLoopResume(self: *State, thread: *Thread, target_frame_count: usize) !?FastLoopResume {
    if (self.gc.running and (self.gc.autoStepDue() or self.stressPending())) {
        if (self.gc.shouldRunAuto() or self.stressPending()) try self.gc.autoStep(thread);
    }
    const frame_count = thread.frames.items.len;
    if (frame_count <= target_frame_count) return null;
    if (thread.pending_unwind_error != null or thread.pending_yield_hook_return) return null;
    const pending = call_mod.hasPendingContinuations(thread);
    if (pending and frame_count <= thread.continuation_frame_count) return null;
    if (thread.hook != .nil or self.options.trace_vm or self.budget.fastLoopInterrupted() or self.stressPending()) return null;
    if (thread.frames.items[frame_count - 1].pc >= thread.frames.items[frame_count - 1].closure.proto.instructions.items.len) return null;
    return .{
        .allowance = self.budget.fastLoopAllowance(),
        .return_floor = if (thread.hook_return) std.math.maxInt(usize) else if (pending) @max(target_frame_count, thread.continuation_frame_count) else target_frame_count,
    };
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
    if (index <= table.array.len) {
        const slot = &table.array.items()[index - 1];
        if (slot.* == .nil and !index_mod.noNewindexMetamethod(table)) return false;
        slot.* = value;
        self.gc.writeTableBarrier(table, key_value, value);
        return true;
    }
    if (value == .nil or !index_mod.noNewindexMetamethod(table)) return false;
    if (index == table.array.len + 1 and index <= table.array.capacity) {
        table.array.appendAssumeCapacity(value);
        table.removeHashKey(key_value);
        self.gc.writeTableBarrier(table, key_value, value);
        return true;
    }
    return false;
}

noinline fn fastTableDynamicKeySetNoAlloc(self: *State, table_value: Value, key: Value, value: Value) bool {
    if (key != .string) return false;
    return fastTableKnownKeySetExistingNoAlloc(self, table_value, key, value);
}

/// `key` must be a string.
fn fastTableKnownKeySetExistingNoAlloc(self: *State, table_value: Value, key: Value, value: Value) bool {
    if (table_value != .table or !key.string.isShort()) return false;
    const table = table_value.table;
    if (table.rollback) |record| if (!record.header.detached) return false;
    if (table.findStringKey(key.string)) |index| {
        const slot = &table.entries()[index].value;
        if (slot.* == .nil) {
            if (!index_mod.noNewindexMetamethod(table)) return false;
            table.invalidateMetaEvents();
            slot.* = value;
            self.gc.writeTableBarrier(table, key, value);
            return true;
        }
        slot.* = value;
        self.gc.writeExistingKeyBarrier(table, key, value);
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
    try rollback_mod.tableWritable(table);
    if (index <= table.array.len) {
        const slot = &table.array.items()[index - 1];
        if (slot.* != .nil or index_mod.noNewindexMetamethod(table)) {
            slot.* = value;
            self.gc.writeTableBarrier(table, key_value, value);
            return true;
        }
        return false;
    }
    if (value == .nil or !index_mod.noNewindexMetamethod(table)) return false;
    if (index == table.array.len + 1) {
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        try table.reserveArray(self.allocator, index);
        table.array.appendAssumeCapacity(value);
        table.removeHashKey(key_value);
        self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
        self.gc.writeTableBarrier(table, key_value, value);
        return true;
    }
    if (index > table.array.capacity) return false;

    const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
    table.extendArrayAssumeCapacity(index);
    table.array.items()[index - 1] = value;
    self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
    self.gc.writeTableBarrier(table, key_value, value);
    return true;
}

fn setTableArrayRawIndex(self: *State, table: *Table, index_u32: u32, value: Value) !void {
    try rollback_mod.tableWritable(table);
    const index: usize = index_u32;
    const key = Value{ .integer = @intCast(index_u32) };
    if (index <= table.array.len) {
        table.array.items()[index - 1] = value;
        self.gc.writeTableBarrier(table, key, value);
        return;
    }
    if (value == .nil) return;
    if (index == table.array.len + 1) {
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        try table.reserveArray(self.allocator, index);
        table.array.appendAssumeCapacity(value);
        self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
        self.gc.writeTableBarrier(table, key, value);
        return;
    }
    if (index <= table.array.capacity) {
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        table.extendArrayAssumeCapacity(index);
        table.array.items()[index - 1] = value;
        self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
        self.gc.writeTableBarrier(table, key, value);
        return;
    }
    try self.setTableRaw(table, key, value);
}

fn fastTableKnownKeySet(self: *State, table_value: Value, key: Value, value: Value) !bool {
    if (table_value != .table or !key.string.isShort()) return false;
    const table = table_value.table;
    if (table.rollback != null and table.get(key) != .nil) try rollback_mod.tableWritable(table);
    if (table.setExistingNonNil(key, value)) {
        self.gc.writeTableBarrier(table, key, value);
        return true;
    }
    if (!index_mod.noNewindexMetamethod(table)) return false;
    if (value == .nil) return true;
    try self.setTableRaw(table, key, value);
    return true;
}

fn traceInstruction(self: *State, frame: CallFrame, pc: usize, instruction: bytecode.Instruction) !void {
    const line = if (pc < frame.closure.proto.line_info.items.len) frame.closure.proto.line_info.items[pc].line else 0;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(self.allocator);
    try appendFmt(self.allocator, &text, "[trace-vm] {s}:{d} pc={d} op={s}\n", .{ frame.closure.proto.source_name, line, pc, @tagName(instruction) });
    try io_mod.writeStderr(self, text.items);
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

pub fn jumpThread(self: *State, thread: *Thread, offset: bytecode.JumpOffset, auto_gc: bool) !void {
    const frame_index = thread.frames.items.len - 1;
    const frame = &thread.frames.items[frame_index];
    const source_pc = frame.pc;
    const target_pc = jumpTarget(source_pc, offset);
    if (source_pc != 0 and frame.closure.proto.jumpExitsToBeClosed(source_pc - 1)) try upvalue_mod.closeToBeClosedExitingPc(self, thread, frame_index, source_pc, target_pc, null);
    thread.frames.items[frame_index].pc = @intCast(target_pc);
    if (target_pc < source_pc) {
        thread.clearHookLine(frame_index);
        if (auto_gc and self.gc.running and self.gc.shouldRunAuto()) try self.gc.autoStep(thread);
    }
}

pub fn jumpThreadMaybeFast(self: *State, thread: *Thread, offset: bytecode.JumpOffset, auto_gc: bool) !void {
    const frame_index = thread.frames.items.len - 1;
    const frame = &thread.frames.items[frame_index];
    if (frame.closure.proto.has_to_close_locals) return jumpThread(self, thread, offset, auto_gc);

    const source_pc = frame.pc;
    const target_pc = jumpTarget(source_pc, offset);
    frame.pc = @intCast(target_pc);
    if (target_pc < source_pc) {
        thread.clearHookLine(frame_index);
        if (auto_gc and self.gc.running and self.gc.shouldRunAuto()) try self.gc.autoStep(thread);
    }
}

/// `key` must be a string.
fn setFieldValue(self: *State, thread: *Thread, table_value: Value, key: Value, value: Value) !void {
    if (!fastTableKnownKeySetExistingNoAlloc(self, table_value, key, value) and
        !try fastTableKnownKeySet(self, table_value, key, value))
    {
        try index_mod.setTableFromThreadContinuable(self, thread, table_value, key, value);
    }
}

fn forPrep(self: *State, thread: *Thread, op: bytecode.ForLoop) !void {
    const initial = get(self, thread, op.base);
    const limit = get(self, thread, op.base + 1);
    const step = get(self, thread, op.base + 2);
    self.budget.noteLongString(initial);
    self.budget.noteLongString(limit);
    self.budget.noteLongString(step);
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
            const count = integerForCount(initial_integer, limit_integer, step_integer);
            set(self, thread, op.base, .{ .integer = initial_integer });
            set(self, thread, op.base + 1, .{ .integer = @bitCast(count orelse 0) });
            set(self, thread, op.base + 2, .{ .integer = step_integer });
            if (count == null) try jumpThread(self, thread, op.offset, false);
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
    const frame_index = thread.frames.items.len - 1;
    const frame = &thread.frames.items[frame_index];
    const absolute_base = frame.base + op.base;
    const stack = thread.stack.items;
    const current = stack[absolute_base];
    const limit = stack[absolute_base + 1];
    const step = stack[absolute_base + 2];
    if (current == .integer and limit == .integer and step == .integer) {
        const count: u64 = @bitCast(limit.integer);
        if (count != 0) {
            stack[absolute_base + 1] = .{ .integer = @bitCast(count - 1) };
            stack[absolute_base] = .{ .integer = current.integer +% step.integer };
            if (frame.closure.proto.has_to_close_locals) {
                try jumpThread(self, thread, op.offset, false);
            } else {
                const source_pc = frame.pc;
                const target_pc = jumpTarget(source_pc, op.offset);
                frame.pc = @intCast(target_pc);
                if (target_pc < source_pc) thread.clearHookLine(frame_index);
            }
        }
        return;
    }

    const current_number = toNumber(current) catch return failure_mod.failRuntimeDetail(self, thread, "'for' initial value must be a number");
    const limit_number = toNumber(limit) catch return failure_mod.failRuntimeDetail(self, thread, "'for' limit must be a number");
    const step_number = toNumber(step) catch return failure_mod.failRuntimeDetail(self, thread, "'for' step must be a number");
    const next = current_number + step_number;
    stack[absolute_base] = .{ .number = next };
    if (forLoopContinuesNumber(next, limit_number, step_number)) {
        if (frame.closure.proto.has_to_close_locals) {
            try jumpThread(self, thread, op.offset, false);
        } else {
            const source_pc = frame.pc;
            const target_pc = jumpTarget(source_pc, op.offset);
            frame.pc = @intCast(target_pc);
            if (target_pc < source_pc) thread.clearHookLine(frame_index);
        }
    }
}

fn setList(self: *State, thread: *Thread, op: bytecode.SetList) !void {
    const frame = thread.frames.items[thread.frames.items.len - 1];
    const source_start = frame.base + op.first;
    const count: usize = if (op.count == bytecode.set_list_multret) try call_mod.resolveResultCount(self, thread, source_start, bytecode.multret_count) else op.count;
    self.budget.note(budget_mod.cost.registers(count));
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
    try rollback_mod.tableWritable(table);
    if (table.metatable != null) return false;

    const start_index: usize = start_index_u32;
    var grow_to: usize = table.array.len;
    for (0..count) |offset| {
        if (offset > std.math.maxInt(usize) - start_index) return self.fail("table overflow");
        const array_index = start_index + offset;
        if (array_index > std.math.maxInt(i64)) return false;
        if (thread.stack.items[source_start + offset] != .nil and array_index > grow_to) grow_to = array_index;
    }

    if (grow_to > table.array.len and start_index > table.array.len + 1 and grow_to > table.array.capacity) return false;
    if (grow_to > table.array.len) {
        const old_capacity_bytes = gc_mod.tableCapacityBytes(table);
        try table.reserveArray(self.allocator, grow_to);
        table.extendArrayAssumeCapacity(grow_to);
        self.gc.noteTableCapacityDelta(table, old_capacity_bytes);
    }

    for (0..count) |offset| {
        const array_index = start_index + offset;
        if (array_index > table.array.len) continue;
        const value = thread.stack.items[source_start + offset];
        table.array.items()[array_index - 1] = value;
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
    return pc +% @as(usize, @bitCast(@as(isize, offset)));
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
        .compare_branch_k,
        .add_k,
        .sub_k,
        .mul_k,
        .div_k,
        .idiv_k,
        .mod_k,
        .band_k,
        .bor_k,
        .bxor_k,
        .shl_k,
        .shr_k,
        .get_method,
        .get_upvalue_field,
        .set_upvalue_field,
        .set_field_k,
        .get_index,
        .set_index,
        .jmp,
        .test_op,
        .test_set,
        .for_prep,
        .for_loop,
        .tfor_prep,
        .tfor_loop,
        .new_table,
        .set_list,
        .vararg,
        .call,
        .tail_call,
        .ret,
        .close,
        => true,
        else => false,
    };
}

/// Iterations after the first of an integer loop, or null when it runs none. `step` must not be zero.
inline fn integerForCount(initial: i64, limit: i64, step: i64) ?u64 {
    if (step > 0) {
        if (initial > limit) return null;
        const span = @as(u64, @bitCast(limit)) -% @as(u64, @bitCast(initial));
        return if (step == 1) span else span / @as(u64, @bitCast(step));
    }
    if (initial < limit) return null;
    const span = @as(u64, @bitCast(initial)) -% @as(u64, @bitCast(limit));
    return span / (@as(u64, @bitCast(-(step + 1))) + 1);
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
    if (index > table.array.len) return null;
    const value = loadValue(&table.array.items()[index - 1]);
    if (value != .nil or index_mod.noIndexMetamethod(table)) return value;
    return null;
}

pub fn assertProtoPrepared(proto: *const proto_mod.Proto) void {
    std.debug.assert(proto.runtime_prepared or proto.constants.items.len == 0);
}

inline fn globalGet(self: *State, key: *const String) Value {
    const table = self.global_table orelse return .nil;
    return table.getString(key);
}

/// Overwrites an existing non-nil global in place, like `State.setGlobal` without interning.
fn fastGlobalSetExisting(self: *State, key: *const String, value: Value) bool {
    if (value == .nil) return false;
    const table = self.global_table orelse return false;
    if (table.rollback) |record| if (!record.header.detached) return false;
    const index = table.findStringKey(key) orelse return false;
    const entry = &table.entries()[index];
    if (entry.value == .nil) return false;
    entry.value = value;
    self.gc.writeExistingKeyBarrier(table, entry.key, value);
    self.gc.markValue(value);
    return true;
}

/// A string's method through its metatable's `__index` table, when that needs no metamethod call.
fn stringMethod(self: *State, key: *const String) ?Value {
    if (!key.isShort()) return null;
    const metatable = self.string_metatable orelse return null;
    const handler = metatable.metaEvent(.__index);
    if (handler != .table) return null;
    const value = handler.table.getString(key);
    if (value != .nil or index_mod.noIndexMetamethod(handler.table)) return value;
    return null;
}

/// A userdata's field through its metatable's `__index` table, when that needs no metamethod call.
fn userdataField(userdata: *const types.Userdata, key: *const String) ?Value {
    if (!key.isShort()) return null;
    const metatable = userdata.metatable orelse return null;
    const handler = metatable.metaEvent(.__index);
    if (handler != .table) return null;
    const value = handler.table.getString(key);
    if (value != .nil or index_mod.noIndexMetamethod(handler.table)) return value;
    return null;
}

fn fastTableFieldGet(table_value: Value, key: *const String) ?Value {
    if (table_value != .table or !key.isShort()) return null;
    const table = table_value.table;
    const value = table.getString(key);
    if (value != .nil) return value;
    const metatable = table.metatable orelse return value;
    if (metatable.metaEventAbsent(.__index)) return value;
    const handler = metatable.metaEvent(.__index);
    if (handler == .nil) return value;
    if (handler != .table) return null;
    const inherited = handler.table.getString(key);
    if (inherited != .nil or index_mod.noIndexMetamethod(handler.table)) return inherited;
    return null;
}

fn fastTableRawGet(table_value: Value, key_value: Value) ?Value {
    if (fastTableArrayGet(table_value, key_value)) |value| return value;
    // Float keys need normalization to integers first.
    if (table_value != .table or key_value == .number) return null;
    if (key_value == .string and !key_value.string.isShort()) return null;
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
