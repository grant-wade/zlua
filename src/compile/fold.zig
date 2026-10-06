//! Compile-time folding of numeric constant expressions.
//!
//! Mirrors PUC Lua 5.5 `constfolding`/`validop` in lcode.c: only numeric
//! literals fold, operations that may raise errors are left for the runtime,
//! and float results that are NaN or zero (either sign) are never folded.
//! The arithmetic matches the VM's raw arithmetic so folded and unfolded
//! evaluation agree bit for bit.

const std = @import("std");
const frontend = @import("../frontend.zig");
const ast = frontend.ast;
const bytecode = @import("bytecode.zig");
const value_mod = @import("../runtime/value.zig");

pub const Numeral = union(enum) {
    integer: i64,
    number: f64,
};

/// Large enough for any rendered i64 or shortest round-trip f64.
pub const render_buffer_len = 40;

pub fn literal(expr: *const ast.Expr) ?Numeral {
    return switch (expr.*) {
        .integer => |token| switch (value_mod.parseIntegerLiteral(token.lexeme) catch return null) {
            .integer => |integer| .{ .integer = integer },
            .number => |number| .{ .number = number },
            else => null,
        },
        .float => |token| .{ .number = value_mod.parseLuaNumber(token.lexeme) catch return null },
        else => null,
    };
}

pub fn foldsUnary(op: ast.UnaryOp) bool {
    return op == .negate or op == .bit_not;
}

pub fn foldsBinary(op: ast.BinaryOp) bool {
    return switch (op) {
        .add, .sub, .mul, .div, .idiv, .mod, .pow, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right => true,
        else => false,
    };
}

pub fn unary(op: ast.UnaryOp, operand: Numeral) ?Numeral {
    const result: Numeral = switch (op) {
        .negate => switch (operand) {
            .integer => |integer| .{ .integer = 0 -% integer },
            .number => |number| .{ .number = -number },
        },
        .bit_not => .{ .integer = ~(exactInteger(operand) orelse return null) },
        .not, .length => return null,
    };
    return accept(result);
}

pub fn binary(op: ast.BinaryOp, lhs: Numeral, rhs: Numeral) ?Numeral {
    const result: Numeral = switch (op) {
        .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right => blk: {
            const left = exactInteger(lhs) orelse return null;
            const right = exactInteger(rhs) orelse return null;
            break :blk .{ .integer = switch (op) {
                .bit_and => left & right,
                .bit_or => left | right,
                .bit_xor => left ^ right,
                .shift_left => shiftLeft(left, right),
                .shift_right => if (right == std.math.minInt(i64)) 0 else shiftLeft(left, -right),
                else => unreachable,
            } };
        },
        .div, .idiv, .mod => blk: {
            // Division by zero either raises an error or produces a value
            // PUC prefers to compute at run time.
            if (toFloat(rhs) == 0) return null;
            break :blk arithmetic(op, lhs, rhs);
        },
        .add, .sub, .mul, .pow => arithmetic(op, lhs, rhs),
        else => return null,
    };
    return accept(result);
}

/// Renders a folded value in the lexeme form the VM's constant loader parses.
pub fn constant(buffer: *[render_buffer_len]u8, value: Numeral) bytecode.Constant {
    return switch (value) {
        .integer => |integer| .{ .integer = std.fmt.bufPrint(buffer, "{d}", .{integer}) catch unreachable },
        .number => |number| .{ .number = if (std.math.isPositiveInf(number))
            "1e999"
        else if (std.math.isNegativeInf(number))
            "-1e999"
        else
            std.fmt.bufPrint(buffer, "{e}", .{number}) catch unreachable },
    };
}

fn accept(result: Numeral) ?Numeral {
    switch (result) {
        .integer => return result,
        // Folding neither NaN nor 0.0 avoids problems with -0.0.
        .number => |number| return if (std.math.isNan(number) or number == 0) null else result,
    }
}

fn arithmetic(op: ast.BinaryOp, lhs: Numeral, rhs: Numeral) Numeral {
    if (op != .div and op != .pow and lhs == .integer and rhs == .integer) {
        const left = lhs.integer;
        const right = rhs.integer;
        return .{ .integer = switch (op) {
            .add => left +% right,
            .sub => left -% right,
            .mul => left *% right,
            .idiv => if (right == -1) 0 -% left else @divFloor(left, right),
            .mod => if (right == -1) 0 else @mod(left, right),
            else => unreachable,
        } };
    }
    const left = toFloat(lhs);
    const right = toFloat(rhs);
    return .{ .number = switch (op) {
        .add => left + right,
        .sub => left - right,
        .mul => left * right,
        .div => left / right,
        .idiv => @floor(left / right),
        .mod => floorModNumber(left, right),
        .pow => std.math.pow(f64, left, right),
        else => unreachable,
    } };
}

fn toFloat(value: Numeral) f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .number => |number| number,
    };
}

fn exactInteger(value: Numeral) ?i64 {
    return switch (value) {
        .integer => |integer| integer,
        .number => |number| value_mod.floatToInteger(number),
    };
}

fn shiftLeft(value: i64, amount: i64) i64 {
    if (amount == 0) return value;
    if (amount >= 64 or amount <= -64) return 0;
    return if (amount > 0)
        value << @intCast(amount)
    else
        @as(i64, @bitCast(@as(u64, @bitCast(value)) >> @intCast(-amount)));
}

fn floorModNumber(left: f64, right: f64) f64 {
    var result = @rem(left, right);
    if (result != 0 and ((result < 0) != (right < 0))) result += right;
    return result;
}

fn expectFolds(expected: Numeral, actual: ?Numeral) !void {
    const value = actual orelse return error.TestExpectedFold;
    try std.testing.expectEqual(std.meta.activeTag(expected), std.meta.activeTag(value));
    switch (expected) {
        .integer => |integer| try std.testing.expectEqual(integer, value.integer),
        .number => |number| try std.testing.expectEqual(number, value.number),
    }
}

test "folds like PUC validop and constfolding" {
    const max = std.math.maxInt(i64);
    const min = std.math.minInt(i64);
    try expectFolds(.{ .integer = min }, binary(.add, .{ .integer = max }, .{ .integer = 1 }));
    try expectFolds(.{ .integer = min }, binary(.idiv, .{ .integer = min }, .{ .integer = -1 }));
    try expectFolds(.{ .integer = 0 }, binary(.mod, .{ .integer = min }, .{ .integer = -1 }));
    try expectFolds(.{ .number = 3.5 }, binary(.div, .{ .integer = 7 }, .{ .integer = 2 }));
    try expectFolds(.{ .integer = 3 }, binary(.bit_or, .{ .number = 3.0 }, .{ .integer = 0 }));
    try expectFolds(.{ .integer = 0 }, binary(.shift_left, .{ .integer = 1 }, .{ .integer = 64 }));
    try expectFolds(.{ .integer = -6 }, unary(.bit_not, .{ .number = 5.0 }));
    try expectFolds(.{ .integer = min }, unary(.negate, .{ .integer = min }));

    try std.testing.expect(binary(.idiv, .{ .integer = 1 }, .{ .integer = 0 }) == null);
    try std.testing.expect(binary(.mod, .{ .integer = 1 }, .{ .number = 0.0 }) == null);
    try std.testing.expect(binary(.div, .{ .integer = 1 }, .{ .integer = 0 }) == null);
    try std.testing.expect(binary(.idiv, .{ .integer = 3 }, .{ .number = -0.0 }) == null);
    try std.testing.expect(binary(.bit_or, .{ .number = 1.5 }, .{ .integer = 0 }) == null);
    try std.testing.expect(binary(.sub, .{ .number = 1.0 }, .{ .number = 1.0 }) == null);
    try std.testing.expect(binary(.concat, .{ .integer = 1 }, .{ .integer = 2 }) == null);
    try std.testing.expect(unary(.negate, .{ .number = 0.0 }) == null);
    try std.testing.expect(unary(.negate, .{ .integer = 0 }) != null);
}

test "rendered constants round-trip through the VM literal parsers" {
    var buffer: [render_buffer_len]u8 = undefined;
    for ([_]Numeral{
        .{ .integer = std.math.minInt(i64) },
        .{ .integer = std.math.maxInt(i64) },
        .{ .number = 1.0 / 3.0 },
        .{ .number = -5e-324 },
        .{ .number = std.math.inf(f64) },
        .{ .number = -std.math.inf(f64) },
        .{ .number = 1.7976931348623157e308 },
    }) |value| {
        switch (constant(&buffer, value)) {
            .integer => |text| try std.testing.expectEqual(value.integer, (try value_mod.parseIntegerLiteral(text)).integer),
            .number => |text| try std.testing.expectEqual(value.number, try value_mod.parseLuaNumber(text)),
            else => return error.TestUnexpectedResult,
        }
    }
}
