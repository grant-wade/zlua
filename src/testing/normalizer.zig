const std = @import("std");
const metadata = @import("metadata.zig");

pub fn normalizeText(
    allocator: std.mem.Allocator,
    input: []const u8,
    mode: metadata.Normalize,
    cwd: []const u8,
) ![]u8 {
    switch (mode) {
        .none => return allocator.dupe(u8, input),
        .paths => return if (cwd.len == 0) allocator.dupe(u8, input) else std.mem.replaceOwned(u8, allocator, input, cwd, "<cwd>"),
    }
}

test "path normalizer replaces cwd" {
    const out = try normalizeText(std.testing.allocator, "/tmp/project/file.lua", .paths, "/tmp/project");
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.eql(u8, out, "<cwd>/file.lua"));
}

test "path normalizer handles empty cwd and repeated matches" {
    const allocator = std.testing.allocator;
    const unchanged = try normalizeText(allocator, "abc", .paths, "");
    defer allocator.free(unchanged);
    try std.testing.expectEqualStrings("abc", unchanged);
    const repeated = try normalizeText(allocator, "/cwd/a /cwd/b", .paths, "/cwd");
    defer allocator.free(repeated);
    try std.testing.expectEqualStrings("<cwd>/a <cwd>/b", repeated);
}
