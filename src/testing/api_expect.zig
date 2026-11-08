const std = @import("std");
const api = @import("../api.zig");

pub fn expectString(expected: []const u8, result: anyerror!api.String) !void {
    var string = try result;
    defer string.deinit();
    try std.testing.expectEqualStrings(expected, try string.bytes());
}
