const types = @import("types.zig");

const Thread = types.Thread;

pub fn checkExecutionLimits(comptime State: type, self: *State, thread: *Thread) !void {
    if (self.options.max_instructions) |max_instructions| {
        if (self.instruction_count >= max_instructions) return self.failRuntimeDetail(thread, "instruction limit exceeded");
    }
    self.instruction_count = self.instruction_count +| 1;
}
