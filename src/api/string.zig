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
};
