const runtime = @import("../runtime.zig");
const callbacks = @import("callbacks.zig");
const convert = @import("convert.zig");
const State = @import("state.zig").State;
const Value = @import("value.zig").Value;

/// Rooted handle to any Lua value; unlike `Value.string`, keeps string bytes alive.
pub const Ref = struct {
    state: *State,
    index: usize,
    generation: u64,

    pub fn deinit(self: *Ref) void {
        if (self.generation == self.state.generation) self.state.raw_state.unrootValue(self.index);
        self.* = undefined;
    }

    pub fn value(self: Ref) !Value {
        return convert.fromRuntimeValue(self.state, try rawValue(self), Value);
    }
};

pub fn fromRuntime(state: *State, raw: runtime.Value) !Ref {
    return .{ .state = state, .generation = state.generation, .index = try state.raw_state.rootValue(raw) };
}

pub fn validate(ref: Ref, state: *State) !void {
    if (ref.state != state or ref.generation != state.generation) return error.InvalidHandle;
}

pub fn rawValue(ref: Ref) !runtime.Value {
    try validate(ref, ref.state);
    callbacks.bindDispatch(ref.state);
    return ref.state.raw_state.rootedValue(ref.index);
}
