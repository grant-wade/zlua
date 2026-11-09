const std = @import("std");
const handle = @import("handle.zig");
const Ref = handle.Ref;

/// Rooted handle to a Lua string.
pub const String = struct {
    ref: Ref,

    pub fn deinit(self: *String) void {
        self.ref.deinit();
        self.* = undefined;
    }

    /// The string's bytes, valid until `deinit` or `State.reset`.
    pub fn bytes(self: String) ![]const u8 {
        return switch (try handle.rawValue(self.ref)) {
            .string => |string| string.bytes(),
            else => error.TypeMismatch,
        };
    }

    /// Writes the string's bytes for the `{f}` format specifier.
    pub fn format(self: String, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.bytes() catch return error.WriteFailed);
    }

    /// A copy of the string's bytes owned by `allocator`.
    pub fn dupe(self: String, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, try self.bytes());
    }
};
