const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const compiler = try zlua.State.init(allocator, .{});
    defer compiler.deinit();

    var chunk = try compiler.loadString(
        \\return greeting .. ", " .. ...
    , .{ .name = "=bytecode_roundtrip" });
    defer chunk.deinit();

    var bytecode: std.Io.Writer.Allocating = .init(allocator);
    defer bytecode.deinit();
    try chunk.dumpBytecode(&bytecode.writer, .{ .strip_debug = true });

    const runner = try zlua.State.init(allocator, .{});
    defer runner.deinit();

    var env = try runner.newTable(.{ .hash_hint = 1 });
    defer env.deinit();
    try env.set("greeting", "hello");

    var cached = try runner.loadBytecode(bytecode.written(), .{ .environment = env });
    defer cached.deinit();

    var message = try cached.call(.{"bytecode"}, zlua.String);
    defer message.deinit();
    std.debug.print("{f}\n", .{message});
}
