const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var host_add = try lua.register("host_add", hostAdd);
    defer host_add.deinit();
    try lua.setGlobal("host_add", host_add);

    var chunk = try lua.loadString(
        \\local sum, status = host_add(20, 22)
        \\return sum, status
    , .{ .name = "=register_function" });
    defer chunk.deinit();

    const Result = zlua.Tuple(&.{ i64, zlua.String });
    var result = try chunk.call(.{}, Result);
    defer result.deinit();

    std.debug.print("{d} {s}\n", .{ result.get(0), try result.get(1).bytes() });
}

fn hostAdd(ctx: *zlua.Context) !void {
    const lhs = try ctx.arg(0, i64);
    const rhs = try ctx.arg(1, i64);
    try ctx.returnValues(.{ lhs + rhs, "ok" });
}
