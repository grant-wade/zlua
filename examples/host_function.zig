const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var host_add = try lua.newFunction("host_add", hostAdd);
    defer host_add.deinit();
    try lua.setGlobal("host_add", host_add);

    var chunk = try lua.loadString(
        \\local sum, status = host_add(20, 22)
        \\return sum, status
    , .{ .name = "=host_function" });
    defer chunk.deinit();

    const sum, var status = try chunk.call(.{}, struct { i64, zlua.String });
    defer status.deinit();

    std.debug.print("{d} {f}\n", .{ sum, status });
}

fn hostAdd(ctx: *zlua.Context) !void {
    const lhs = try ctx.arg(0, i64);
    const rhs = try ctx.arg(1, i64);
    try ctx.returnValues(.{ lhs + rhs, "ok" });
}
