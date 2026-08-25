const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var lua = try zlua.State.init(allocator, .{
        .stdlib = .{ .custom = .{
            .math = true,
            .json = true,
        } },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local point = json.read([[{"x": 3, "y": 4}]])
        \\return math.sqrt(point.x ^ 2 + point.y ^ 2)
    , .{ .name = "=select_libraries" });
    defer chunk.deinit();

    const distance = try chunk.call(.{}, f64);
    std.debug.print("distance = {d}\n", .{distance});
}
