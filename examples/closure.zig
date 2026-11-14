const std = @import("std");
const zlua = @import("zlua");

fn advance(ctx: *zlua.Context) !i64 {
    const step = try ctx.upvalue(1, i64);
    const total = try ctx.upvalue(0, i64) + step;
    try ctx.setUpvalue(0, total);
    return total;
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var by_one = try lua.newClosure("by_one", advance, .{ @as(i64, 0), @as(i64, 1) });
    defer by_one.deinit();
    var by_ten = try lua.newClosure("by_ten", advance, .{ @as(i64, 100), @as(i64, 10) });
    defer by_ten.deinit();
    try lua.setGlobals(.{ .by_one = by_one, .by_ten = by_ten });

    var chunk = try lua.loadString(
        \\by_one()
        \\by_one()
        \\return by_one(), by_ten()
    , .{ .name = "=closure" });
    defer chunk.deinit();

    const ones, const tens = try chunk.call(.{}, struct { i64, i64 });
    std.debug.print("by_one={d} by_ten={d}\n", .{ ones, tens });
    std.debug.print("by_one from Zig={d}\n", .{try by_one.call(.{}, i64)});
}
