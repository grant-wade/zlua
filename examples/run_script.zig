const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local name = ...
        \\return "hello, " .. name
    , .{ .name = "=run_script" });
    defer chunk.deinit();

    var message = try chunk.call(.{"zlua"}, zlua.String);
    defer message.deinit();
    std.debug.print("{f}\n", .{message});
}
