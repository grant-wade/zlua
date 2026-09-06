const std = @import("std");
const Dir = std.Io.Dir;

pub fn discoverTests(allocator: std.mem.Allocator, io: std.Io, root: []const u8, suffix: []const u8, tests: *std.ArrayList([]u8)) !void {
    var dir = Dir.cwd().openDir(io, root, .{ .iterate = true }) catch |err| switch (err) {
        error.NotDir => {
            if (std.mem.endsWith(u8, root, suffix)) try tests.append(allocator, try allocator.dupe(u8, root));
            return;
        },
        else => return err,
    };
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, suffix)) continue;
        try tests.append(allocator, try std.fs.path.join(allocator, &.{ root, entry.path }));
    }
}
