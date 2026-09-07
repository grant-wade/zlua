const std = @import("std");
const metadata = @import("metadata.zig");

pub fn normalizeText(
    allocator: std.mem.Allocator,
    input: []const u8,
    mode: metadata.Normalize,
    cwd: []const u8,
) ![]u8 {
    // These harnesses compare text. CLua's Windows CRT and Git checkouts can
    // produce CRLF, while the in-process VM writes LF. Preserve lone CRs.
    const text = try std.mem.replaceOwned(u8, allocator, input, "\r\n", "\n");
    errdefer allocator.free(text);
    switch (mode) {
        .none => return text,
        .paths => {
            if (cwd.len == 0) return text;
            const result = try std.mem.replaceOwned(u8, allocator, text, cwd, "<cwd>");
            allocator.free(text);
            return result;
        },
    }
}

pub fn textEqual(lhs: []const u8, rhs: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < lhs.len and j < rhs.len) {
        if (lhs[i] == '\r' and i + 1 < lhs.len and lhs[i + 1] == '\n') i += 1;
        if (rhs[j] == '\r' and j + 1 < rhs.len and rhs[j + 1] == '\n') j += 1;
        if (lhs[i] != rhs[j]) return false;
        i += 1;
        j += 1;
    }
    return i == lhs.len and j == rhs.len;
}

test "text comparison normalizes CRLF without hiding other differences" {
    try std.testing.expect(textEqual("a\r\nb\n", "a\nb\r\n"));
    try std.testing.expect(textEqual("", ""));
    try std.testing.expect(!textEqual("a\r", "a"));
    try std.testing.expect(!textEqual("a\n", "a"));
    try std.testing.expect(!textEqual("a \n", "a\n"));
    try std.testing.expect(!textEqual("a\r\n", "b\n"));
    const text = try normalizeText(std.testing.allocator, "a\r\nb\rc\n", .none, "");
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("a\nb\rc\n", text);
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
