const std = @import("std");
const compile = @import("../compile.zig");
const call_mod = @import("call.zig");
const failure_mod = @import("failure.zig");
const metatable_mod = @import("metatable.zig");
const state_mod = @import("state.zig");
const strings_mod = @import("strings.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const State = state_mod.State;
const bytecode = compile.bytecode;
const Value = types.Value;
const BranchContinuation = types.BranchContinuation;
const valuesEqual = value_mod.valuesEqual;
const truthy = value_mod.truthy;
const toInteger = value_mod.toInteger;
const toNumber = value_mod.toNumber;
const toNumberMaybe = value_mod.toNumberMaybe;
const luaStringLike = value_mod.luaStringLike;
const floatToInteger = value_mod.floatToInteger;
const Thread = types.Thread;

fn lengthOf(self: *State, thread: *Thread, value: Value) !Value {
    return switch (value) {
        .string => |string| .{ .integer = @intCast(string.len) },
        .table => |table| if ((try metatable_mod.getMetaEvent(self, value, .__len))) |metamethod|
            try call_mod.callOneMetamethod(self, thread, "__len", metamethod, &.{ value, value })
        else
            .{ .integer = table.len() },
        else => if ((try metatable_mod.getMetaEvent(self, value, .__len))) |metamethod|
            try call_mod.callOneMetamethod(self, thread, "__len", metamethod, &.{ value, value })
        else
            failure_mod.failLengthTypeError(self, thread, value),
    };
}

/// Like `luaL_len`.
pub fn lengthInteger(self: *State, thread: *Thread, value: Value) !i64 {
    return lengthToInteger(self, try lengthOf(self, thread, value));
}

pub fn lengthToInteger(self: *State, length: Value) !i64 {
    return value_mod.coerceToInteger(length) orelse self.failLibrary("object length is not an integer");
}

fn concatValues(self: *State, lhs: Value, rhs: Value) !Value {
    return concatStringValues(self, &.{ lhs, rhs });
}

fn concatStringValues(self: *State, values: []const Value) !Value {
    var texts: [256]u8 = undefined;
    var cached: [16][]const u8 = undefined;
    var cached_count: usize = 0;
    var texts_len: usize = 0;
    var scratch: [value_mod.max_number_text_len]u8 = undefined;
    var total: usize = 0;
    for (values) |value| total +|= switch (value) {
        .string => |string| string.len,
        else => blk: {
            const text = value_mod.formatNumber(&scratch, value);
            if (cached_count < cached.len and texts_len + text.len <= texts.len) {
                @memcpy(texts[texts_len..][0..text.len], text);
                cached[cached_count] = texts[texts_len..][0..text.len];
                cached_count += 1;
                texts_len += text.len;
            }
            break :blk text.len;
        },
    };
    var short: [strings_mod.short_string_limit]u8 = undefined;
    const long = if (total > short.len) try self.strings.createLong(total) else null;
    const out = if (long) |string| string.bytesMut() else short[0..total];
    var offset: usize = 0;
    var number_index: usize = 0;
    for (values) |value| {
        const text = switch (value) {
            .string => |string| string.bytes(),
            else => blk: {
                defer number_index += 1;
                break :blk if (number_index < cached_count) cached[number_index] else value_mod.formatNumber(&scratch, value);
            },
        };
        @memcpy(out[offset..][0..text.len], text);
        offset += text.len;
    }
    if (long) |string| return .{ .string = string };
    return .{ .string = try self.strings.internConstant(out) };
}

pub fn concatRangeToRegister(self: *State, thread: *Thread, op: bytecode.ConcatRange) !void {
    const base = thread.frames.items[thread.frames.items.len - 1].base;
    try finishConcatRange(self, thread, base + op.dest, base + op.first, op.count);
}

/// Like `luaV_concat`. Partial results stay in the operand slots so a yielding
/// `__concat` can resume.
pub fn finishConcatRange(self: *State, thread: *Thread, dest: usize, first: usize, count_in: usize) !void {
    var count = count_in;
    while (count > 1) {
        const operands = thread.stack.items[first .. first + count];
        var run: usize = 0;
        while (run < count and luaStringLike(operands[count - 1 - run])) run += 1;
        if (run >= 2) {
            const joined = try concatStringValues(self, operands[count - run ..]);
            thread.stack.items[first + count - run] = joined;
            count -= run - 1;
            continue;
        }
        const lhs = operands[count - 2];
        const rhs = operands[count - 1];
        const metamethod = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__concat")) orelse return failure_mod.failConcatRangeTypeError(self, thread, lhs, rhs, count - 2);
        const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__concat", metamethod, &.{ lhs, rhs }, .{ .concat = .{ .dest = dest, .first = first, .count = count - 1 } });
        count -= 1;
        thread.stack.items[first + count - 1] = result;
    }
    thread.stack.items[dest] = thread.stack.items[first];
}

pub fn binaryOpToRegister(self: *State, thread: *Thread, op: bytecode.Binary, kind: BinaryOp) !void {
    return binaryValuesToRegister(self, thread, op.dest, vm_mod.get(self, thread, op.left), vm_mod.get(self, thread, op.right), kind);
}

pub fn binaryValuesToRegister(self: *State, thread: *Thread, dest: bytecode.Register, lhs: Value, rhs: Value, kind: BinaryOp) !void {
    if (kind == .concat and luaStringLike(lhs) and luaStringLike(rhs)) {
        vm_mod.set(self, thread, dest, try concatValues(self, lhs, rhs));
        return;
    }
    const raw = rawBinaryOp(lhs, rhs, kind) catch |err| switch (err) {
        error.RuntimeError => if ((kind == .idiv or kind == .mod) and (toInteger(rhs) orelse 1) == 0) return failure_mod.failDivisionByZero(self, thread, lhs, rhs, kind) else return err,
    };
    if (raw) |value| {
        vm_mod.set(self, thread, dest, value);
        return;
    }

    const metamethod_name = binaryMetamethod(kind);
    const metamethod = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, metamethod_name)) orelse {
        return failure_mod.failBinaryTypeError(self, thread, lhs, rhs, kind);
    };
    const result = try call_mod.callOneMetamethodWithContinuation(self, thread, metamethod_name, metamethod, &.{ lhs, rhs }, .{ .value = vm_mod.absoluteRegister(self, thread, dest) });
    vm_mod.set(self, thread, dest, result);
}

pub fn unaryOpToRegister(self: *State, thread: *Thread, op: bytecode.Unary, kind: UnaryMetamethodOp) !void {
    const value = vm_mod.get(self, thread, op.source);
    if (rawUnaryOp(value, kind)) |result| {
        vm_mod.set(self, thread, op.dest, result);
        return;
    }
    const metamethod = (try metatable_mod.getMetamethod(self, value, unaryMetamethod(kind))) orelse return failure_mod.failUnaryTypeError(self, thread, value, kind);
    const result = try call_mod.callOneMetamethodWithContinuation(self, thread, unaryMetamethod(kind), metamethod, &.{ value, value }, .{ .value = vm_mod.absoluteRegister(self, thread, op.dest) });
    vm_mod.set(self, thread, op.dest, result);
}

pub fn equalValuesToRegister(self: *State, thread: *Thread, op: bytecode.Binary) !void {
    const lhs = vm_mod.get(self, thread, op.left);
    const rhs = vm_mod.get(self, thread, op.right);
    if (valuesEqual(lhs, rhs)) {
        vm_mod.set(self, thread, op.dest, .{ .boolean = true });
        return;
    }
    if (!equalityHasMetamethod(lhs, rhs)) {
        vm_mod.set(self, thread, op.dest, .{ .boolean = false });
        return;
    }
    const metamethod = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__eq")) orelse {
        vm_mod.set(self, thread, op.dest, .{ .boolean = false });
        return;
    };
    const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__eq", metamethod, &.{ lhs, rhs }, .{ .truthy = vm_mod.absoluteRegister(self, thread, op.dest) });
    vm_mod.set(self, thread, op.dest, .{ .boolean = truthy(result) });
}

pub fn compareValuesToRegister(self: *State, thread: *Thread, op: bytecode.Binary, kind: CompareOp) !void {
    const lhs = vm_mod.get(self, thread, op.left);
    const rhs = vm_mod.get(self, thread, op.right);
    if (rawCompare(lhs, rhs, kind)) |result| {
        vm_mod.set(self, thread, op.dest, .{ .boolean = result });
        return;
    }
    switch (kind) {
        .lt => {
            const metamethod = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__lt")) orelse return failure_mod.failCompareTypeError(self, thread, lhs, rhs);
            const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__lt", metamethod, &.{ lhs, rhs }, .{ .truthy = vm_mod.absoluteRegister(self, thread, op.dest) });
            vm_mod.set(self, thread, op.dest, .{ .boolean = truthy(result) });
        },
        .le => {
            if (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__le")) |metamethod| {
                const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__le", metamethod, &.{ lhs, rhs }, .{ .truthy = vm_mod.absoluteRegister(self, thread, op.dest) });
                vm_mod.set(self, thread, op.dest, .{ .boolean = truthy(result) });
                return;
            }
            const lt = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__lt")) orelse return failure_mod.failCompareTypeError(self, thread, lhs, rhs);
            const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__lt", lt, &.{ rhs, lhs }, .{ .inverted_truthy = vm_mod.absoluteRegister(self, thread, op.dest) });
            vm_mod.set(self, thread, op.dest, .{ .boolean = !truthy(result) });
        },
    }
}

pub fn compareBranch(self: *State, thread: *Thread, op: bytecode.CompareBranch) !void {
    return compareBranchValues(self, thread, vm_mod.get(self, thread, op.left), vm_mod.get(self, thread, op.right), op.op, op.jump_if_truthy, op.offset);
}

pub fn compareBranchConstant(self: *State, thread: *Thread, op: bytecode.CompareBranchConstant, constant: Value) !void {
    const value = vm_mod.get(self, thread, op.register);
    return switch (op.op) {
        .eq => compareBranchValues(self, thread, value, constant, .eq, op.jump_if_truthy, op.offset),
        .lt => compareBranchValues(self, thread, value, constant, .lt, op.jump_if_truthy, op.offset),
        .le => compareBranchValues(self, thread, value, constant, .le, op.jump_if_truthy, op.offset),
        .gt => compareBranchValues(self, thread, constant, value, .lt, op.jump_if_truthy, op.offset),
        .ge => compareBranchValues(self, thread, constant, value, .le, op.jump_if_truthy, op.offset),
    };
}

fn compareBranchValues(self: *State, thread: *Thread, lhs: Value, rhs: Value, kind: bytecode.CompareBranchOp, jump_if_truthy: bool, offset: bytecode.JumpOffset) !void {
    switch (kind) {
        .eq => {
            if (valuesEqual(lhs, rhs)) return jumpIfBranchResult(self, thread, true, jump_if_truthy, offset);
            if (!equalityHasMetamethod(lhs, rhs)) return jumpIfBranchResult(self, thread, false, jump_if_truthy, offset);
            const metamethod = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__eq")) orelse return jumpIfBranchResult(self, thread, false, jump_if_truthy, offset);
            const continuation: BranchContinuation = .{ .jump_if_truthy = jump_if_truthy, .offset = offset };
            const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__eq", metamethod, &.{ lhs, rhs }, .{ .branch_truthy = continuation });
            try jumpIfBranchResult(self, thread, truthy(result), jump_if_truthy, offset);
        },
        .lt => try compareBranchOrder(self, thread, lhs, rhs, .lt, "__lt", jump_if_truthy, offset),
        .le => {
            if (rawCompare(lhs, rhs, .le)) |result| return jumpIfBranchResult(self, thread, result, jump_if_truthy, offset);
            if (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__le")) |metamethod| {
                const continuation: BranchContinuation = .{ .jump_if_truthy = jump_if_truthy, .offset = offset };
                const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__le", metamethod, &.{ lhs, rhs }, .{ .branch_truthy = continuation });
                return jumpIfBranchResult(self, thread, truthy(result), jump_if_truthy, offset);
            }
            const lt = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__lt")) orelse return failure_mod.failCompareTypeError(self, thread, lhs, rhs);
            const continuation: BranchContinuation = .{ .jump_if_truthy = jump_if_truthy, .offset = offset };
            const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__lt", lt, &.{ rhs, lhs }, .{ .branch_inverted_truthy = continuation });
            try jumpIfBranchResult(self, thread, !truthy(result), jump_if_truthy, offset);
        },
    }
}

fn compareBranchOrder(self: *State, thread: *Thread, lhs: Value, rhs: Value, kind: CompareOp, metamethod_name: []const u8, jump_if_truthy: bool, offset: bytecode.JumpOffset) !void {
    if (rawCompare(lhs, rhs, kind)) |result| return jumpIfBranchResult(self, thread, result, jump_if_truthy, offset);
    const metamethod = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, metamethod_name)) orelse return failure_mod.failCompareTypeError(self, thread, lhs, rhs);
    const continuation: BranchContinuation = .{ .jump_if_truthy = jump_if_truthy, .offset = offset };
    const result = try call_mod.callOneMetamethodWithContinuation(self, thread, metamethod_name, metamethod, &.{ lhs, rhs }, .{ .branch_truthy = continuation });
    try jumpIfBranchResult(self, thread, truthy(result), jump_if_truthy, offset);
}

pub fn jumpIfBranchResult(self: *State, thread: *Thread, result: bool, jump_if_truthy: bool, offset: bytecode.JumpOffset) !void {
    if (result == jump_if_truthy) try vm_mod.jumpThreadMaybeFast(self, thread, offset, true);
}

pub fn lengthToRegister(self: *State, thread: *Thread, op: bytecode.Unary) !void {
    const value = vm_mod.get(self, thread, op.source);
    switch (value) {
        .string => |string| vm_mod.set(self, thread, op.dest, .{ .integer = @intCast(string.len) }),
        .table => |table| if ((try metatable_mod.getMetaEvent(self, value, .__len))) |metamethod| {
            const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__len", metamethod, &.{ value, value }, .{ .value = vm_mod.absoluteRegister(self, thread, op.dest) });
            vm_mod.set(self, thread, op.dest, result);
        } else {
            vm_mod.set(self, thread, op.dest, .{ .integer = table.len() });
        },
        else => if ((try metatable_mod.getMetaEvent(self, value, .__len))) |metamethod| {
            const result = try call_mod.callOneMetamethodWithContinuation(self, thread, "__len", metamethod, &.{ value, value }, .{ .value = vm_mod.absoluteRegister(self, thread, op.dest) });
            vm_mod.set(self, thread, op.dest, result);
        } else {
            return failure_mod.failLengthTypeError(self, thread, value);
        },
    }
}

pub fn compareValues(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: CompareOp) !bool {
    if (rawCompare(lhs, rhs, op)) |result| return result;
    switch (op) {
        .lt => {
            const metamethod = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__lt")) orelse return failure_mod.failCompareTypeError(self, thread, lhs, rhs);
            return truthy(try call_mod.callOneMetamethod(self, thread, "__lt", metamethod, &.{ lhs, rhs }));
        },
        .le => {
            if (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__le")) |metamethod| {
                return truthy(try call_mod.callOneMetamethod(self, thread, "__le", metamethod, &.{ lhs, rhs }));
            }
            const lt = (try metatable_mod.getEitherMetamethod(self, lhs, rhs, "__lt")) orelse return failure_mod.failCompareTypeError(self, thread, lhs, rhs);
            return !truthy(try call_mod.callOneMetamethod(self, thread, "__lt", lt, &.{ rhs, lhs }));
        },
    }
}

pub const BinaryOp = enum { add, sub, mul, div, idiv, mod, pow, band, bor, bxor, shl, shr, concat };

pub const UnaryMetamethodOp = enum { unm, bnot };

pub const CompareOp = enum { lt, le };

pub fn arithmeticVerb(op: BinaryOp) []const u8 {
    return switch (op) {
        .add => "add",
        .sub => "sub",
        .mul => "mul",
        .div => "div",
        .idiv => "idiv",
        .mod => "mod",
        .pow => "pow",
        else => "perform arithmetic on",
    };
}

fn rawBinaryOp(lhs: Value, rhs: Value, op: BinaryOp) !?Value {
    switch (op) {
        .add, .sub, .mul, .idiv, .mod => {
            if (lhs == .integer and rhs == .integer) {
                return switch (op) {
                    .add => .{ .integer = lhs.integer +% rhs.integer },
                    .sub => .{ .integer = lhs.integer -% rhs.integer },
                    .mul => .{ .integer = lhs.integer *% rhs.integer },
                    .idiv => if (rhs.integer == 0) error.RuntimeError else .{ .integer = floorDiv(lhs.integer, rhs.integer) },
                    .mod => if (rhs.integer == 0) error.RuntimeError else .{ .integer = floorMod(lhs.integer, rhs.integer) },
                    else => unreachable,
                };
            }
            if (toInteger(lhs)) |left| {
                if (toInteger(rhs)) |right| {
                    return switch (op) {
                        .add => .{ .integer = left +% right },
                        .sub => .{ .integer = left -% right },
                        .mul => .{ .integer = left *% right },
                        .idiv => if (right == 0) error.RuntimeError else .{ .integer = floorDiv(left, right) },
                        .mod => if (right == 0) error.RuntimeError else .{ .integer = floorMod(left, right) },
                        else => unreachable,
                    };
                }
            }
        },
        .band, .bor, .bxor, .shl, .shr => {
            if (toBitwiseInteger(lhs)) |left| {
                if (toBitwiseInteger(rhs)) |right| {
                    return .{ .integer = rawBitwise(left, right, op) };
                }
            }
        },
        .div, .pow, .concat => {},
    }

    if (op == .concat) return null;
    const left = toNumberMaybe(lhs) orelse return null;
    const right = toNumberMaybe(rhs) orelse return null;
    return switch (op) {
        .add => .{ .number = left + right },
        .sub => .{ .number = left - right },
        .mul => .{ .number = left * right },
        .div => .{ .number = left / right },
        .idiv => .{ .number = @floor(left / right) },
        .mod => .{ .number = floorModNumber(left, right) },
        .pow => .{ .number = std.math.pow(f64, left, right) },
        else => null,
    };
}

pub inline fn rawNumericBinaryOpFast(lhs: Value, rhs: Value, comptime op: BinaryOp) ?Value {
    return switch (lhs) {
        .integer => |left_integer| switch (rhs) {
            .integer => |right_integer| switch (op) {
                .add => .{ .integer = left_integer +% right_integer },
                .sub => .{ .integer = left_integer -% right_integer },
                .mul => .{ .integer = left_integer *% right_integer },
                .idiv => if (right_integer == 0) null else .{ .integer = floorDiv(left_integer, right_integer) },
                .mod => if (right_integer == 0) null else .{ .integer = floorMod(left_integer, right_integer) },
                .div => .{ .number = @as(f64, @floatFromInt(left_integer)) / @as(f64, @floatFromInt(right_integer)) },
                else => null,
            },
            .number => |right_number| switch (op) {
                .add => .{ .number = @as(f64, @floatFromInt(left_integer)) + right_number },
                .sub => .{ .number = @as(f64, @floatFromInt(left_integer)) - right_number },
                .mul => .{ .number = @as(f64, @floatFromInt(left_integer)) * right_number },
                .div => .{ .number = @as(f64, @floatFromInt(left_integer)) / right_number },
                .idiv => .{ .number = @floor(@as(f64, @floatFromInt(left_integer)) / right_number) },
                .mod => .{ .number = floorModNumber(@as(f64, @floatFromInt(left_integer)), right_number) },
                else => null,
            },
            else => null,
        },
        .number => |left_number| switch (rhs) {
            .integer => |right_integer| switch (op) {
                .add => .{ .number = left_number + @as(f64, @floatFromInt(right_integer)) },
                .sub => .{ .number = left_number - @as(f64, @floatFromInt(right_integer)) },
                .mul => .{ .number = left_number * @as(f64, @floatFromInt(right_integer)) },
                .div => .{ .number = left_number / @as(f64, @floatFromInt(right_integer)) },
                .idiv => .{ .number = @floor(left_number / @as(f64, @floatFromInt(right_integer))) },
                .mod => .{ .number = floorModNumber(left_number, @as(f64, @floatFromInt(right_integer))) },
                else => null,
            },
            .number => |right_number| switch (op) {
                .add => .{ .number = left_number + right_number },
                .sub => .{ .number = left_number - right_number },
                .mul => .{ .number = left_number * right_number },
                .div => .{ .number = left_number / right_number },
                .idiv => .{ .number = @floor(left_number / right_number) },
                .mod => .{ .number = floorModNumber(left_number, right_number) },
                else => null,
            },
            else => null,
        },
        else => null,
    };
}

pub inline fn rawIntegerBitwiseOpFast(lhs: Value, rhs: Value, comptime op: BinaryOp) ?Value {
    if (lhs != .integer or rhs != .integer) return null;
    return .{ .integer = rawBitwise(lhs.integer, rhs.integer, op) };
}

pub fn equalityHasMetamethod(lhs: Value, rhs: Value) bool {
    return switch (lhs) {
        .table => |table| rhs == .table and !(metatable_mod.noMetaEvent(table, .__eq) and metatable_mod.noMetaEvent(rhs.table, .__eq)),
        .userdata => rhs == .userdata,
        else => false,
    };
}

pub inline fn rawCompareConstantResult(value: Value, constant: Value, op: bytecode.CompareConstantOp) ?bool {
    return switch (op) {
        .eq => valuesEqual(value, constant),
        .lt => rawCompare(value, constant, .lt),
        .le => rawCompare(value, constant, .le),
        .gt => rawCompare(constant, value, .lt),
        .ge => rawCompare(constant, value, .le),
    };
}

pub fn constantBinaryOp(comptime tag: std.meta.Tag(bytecode.Instruction)) BinaryOp {
    return switch (tag) {
        .add_k => .add,
        .sub_k => .sub,
        .mul_k => .mul,
        .div_k => .div,
        .idiv_k => .idiv,
        .mod_k => .mod,
        .band_k => .band,
        .bor_k => .bor,
        .bxor_k => .bxor,
        .shl_k => .shl,
        .shr_k => .shr,
        else => @compileError("not a constant binary instruction"),
    };
}

pub inline fn rawBinaryOpFast(lhs: Value, rhs: Value, comptime op: BinaryOp) ?Value {
    return switch (op) {
        .band, .bor, .bxor, .shl, .shr => rawIntegerBitwiseOpFast(lhs, rhs, op),
        else => rawNumericBinaryOpFast(lhs, rhs, op),
    };
}

pub fn rawCompareBranchResult(lhs: Value, rhs: Value, op: bytecode.CompareBranchOp) ?bool {
    return switch (op) {
        .eq => if (valuesEqual(lhs, rhs)) true else if (equalityHasMetamethod(lhs, rhs)) null else false,
        .lt => rawCompare(lhs, rhs, .lt),
        .le => rawCompare(lhs, rhs, .le),
    };
}

pub fn floorModNumber(left: f64, right: f64) f64 {
    var result = @rem(left, right);
    if (result != 0 and ((result < 0) != (right < 0))) result += right;
    return result;
}

fn rawUnaryOp(value: Value, op: UnaryMetamethodOp) ?Value {
    return switch (op) {
        .unm => switch (value) {
            .integer => |integer| .{ .integer = -%integer },
            .number => |number| .{ .number = -number },
            .string => if (toInteger(value)) |integer| .{ .integer = -%integer } else if (toNumberMaybe(value)) |number| .{ .number = -number } else null,
            else => null,
        },
        .bnot => if (toBitwiseInteger(value)) |integer| .{ .integer = ~integer } else null,
    };
}

pub fn toBitwiseInteger(value: Value) ?i64 {
    return switch (value) {
        .integer => |integer| integer,
        .number => |number| floatToInteger(number),
        else => null,
    };
}

pub fn isNumber(value: Value) bool {
    return value == .integer or value == .number;
}

fn rawBitwise(left: i64, right: i64, op: BinaryOp) i64 {
    return switch (op) {
        .band => left & right,
        .bor => left | right,
        .bxor => left ^ right,
        .shl => shiftInteger(left, right),
        .shr => if (right == std.math.minInt(i64)) 0 else shiftInteger(left, -right),
        else => unreachable,
    };
}

fn shiftInteger(value: i64, amount: i64) i64 {
    if (amount == 0) return value;
    if (amount >= 64 or amount <= -64) return 0;
    return if (amount > 0)
        value << @intCast(amount)
    else
        @as(i64, @bitCast(@as(u64, @bitCast(value)) >> @intCast(-amount)));
}

pub fn rawCompare(lhs: Value, rhs: Value, op: CompareOp) ?bool {
    return switch (lhs) {
        .integer => |left| switch (rhs) {
            .integer => |right| switch (op) {
                .lt => left < right,
                .le => left <= right,
            },
            .number => |right| compareIntegerNumber(left, right, op),
            else => null,
        },
        .number => |left| switch (rhs) {
            .integer => |right| compareNumberInteger(left, right, op),
            .number => |right| switch (op) {
                .lt => left < right,
                .le => left <= right,
            },
            else => null,
        },
        .string => |left| switch (rhs) {
            .string => |right| switch (op) {
                .lt => std.mem.lessThan(u8, left.bytes(), right.bytes()),
                .le => !std.mem.lessThan(u8, right.bytes(), left.bytes()),
            },
            else => null,
        },
        else => null,
    };
}

fn compareIntegerNumber(integer: i64, number: f64, op: CompareOp) bool {
    if (std.math.isNan(number)) return false;
    const min = @as(f64, @floatFromInt(std.math.minInt(i64)));
    const max_exclusive = -min;
    return switch (op) {
        .lt => {
            if (number <= min) return false;
            if (number >= max_exclusive) return true;
            return integer < @as(i64, @intFromFloat(@ceil(number)));
        },
        .le => {
            if (number < min) return false;
            if (number >= max_exclusive) return true;
            return integer <= @as(i64, @intFromFloat(@floor(number)));
        },
    };
}

fn compareNumberInteger(number: f64, integer: i64, op: CompareOp) bool {
    if (std.math.isNan(number)) return false;
    return switch (op) {
        .lt => !compareIntegerNumber(integer, number, .le),
        .le => !compareIntegerNumber(integer, number, .lt),
    };
}

fn binaryMetamethod(op: BinaryOp) []const u8 {
    return switch (op) {
        .add => "__add",
        .sub => "__sub",
        .mul => "__mul",
        .div => "__div",
        .idiv => "__idiv",
        .mod => "__mod",
        .pow => "__pow",
        .band => "__band",
        .bor => "__bor",
        .bxor => "__bxor",
        .shl => "__shl",
        .shr => "__shr",
        .concat => "__concat",
    };
}

fn unaryMetamethod(op: UnaryMetamethodOp) []const u8 {
    return switch (op) {
        .unm => "__unm",
        .bnot => "__bnot",
    };
}

pub fn lessThan(lhs: Value, rhs: Value) !bool {
    return switch (lhs) {
        .integer, .number => (try toNumber(lhs)) < (try toNumber(rhs)),
        .string => |left| switch (rhs) {
            .string => |right| std.mem.lessThan(u8, left.bytes(), right.bytes()),
            else => error.RuntimeError,
        },
        else => error.RuntimeError,
    };
}

fn floorDiv(left: i64, right: i64) i64 {
    if (left == std.math.minInt(i64) and right == -1) return left;
    return @divFloor(left, right);
}

fn floorMod(left: i64, right: i64) i64 {
    if (left == std.math.minInt(i64) and right == -1) return 0;
    return @mod(left, right);
}
