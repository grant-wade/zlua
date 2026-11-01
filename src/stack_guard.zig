const std = @import("std");
const builtin = @import("builtin");

/// Native stack bytes a state may use by default; hosts on smaller stacks must lower it.
pub const default_max_bytes: usize = if (std.ascii.eqlIgnoreCase(@tagName(builtin.mode), "debug")) 14 << 20 else 6 << 20;

/// Native stack budget measured from the frame that started it.
pub const StackGuard = struct {
    base: usize = 0,
    max_bytes: usize = std.math.maxInt(usize),
    /// Host interrupt request polled by long-running compilation.
    interrupt: ?*const std.atomic.Value(bool) = null,

    pub inline fn start(max_bytes: usize) StackGuard {
        return .{ .base = @frameAddress(), .max_bytes = max_bytes };
    }

    pub inline fn exceeded(self: StackGuard) bool {
        const here = @frameAddress();
        return (if (here > self.base) here - self.base else self.base - here) > self.max_bytes;
    }

    pub inline fn interrupted(self: StackGuard) bool {
        const request = self.interrupt orelse return false;
        return request.load(.monotonic);
    }
};

test "guard allows shallow frames and rejects deep ones" {
    const guard = StackGuard.start(8 * 1024);
    try std.testing.expect(!guard.exceeded());

    const Recurse = struct {
        fn depthUntilExceeded(stack: StackGuard, depth: usize) usize {
            var padding: [512]u8 = undefined;
            std.mem.doNotOptimizeAway(&padding);
            if (stack.exceeded()) return depth;
            return depthUntilExceeded(stack, depth + 1) +| 0;
        }
    };
    try std.testing.expect(Recurse.depthUntilExceeded(guard, 0) > 0);
    try std.testing.expect(!(StackGuard{}).exceeded());
}
