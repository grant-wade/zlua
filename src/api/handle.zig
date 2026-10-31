const std = @import("std");
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
        if (self.generation == self.state.generation) {
            forgetScopedRoot(self.state, self.index);
            self.state.raw_state.unrootValue(self.index);
        }
        self.* = undefined;
    }

    pub fn value(self: Ref) !Value {
        return convert.fromRuntimeValue(self.state, try rawValue(self), Value);
    }
};

/// Releases the handles rooted since `State.handleScope`, except those given to `keep`. Scopes
/// nest and end in reverse order, as `defer scope.end()` does.
pub const HandleScope = struct {
    state: *State,
    generation: u64,
    start: usize,
    previous_start: usize,

    pub fn end(self: *HandleScope) void {
        const state = self.state;
        if (self.generation != state.generation) return;
        for (state.scoped_roots.items[self.start..]) |index| {
            if (index != released_root) state.raw_state.unrootValue(index);
        }
        state.scoped_roots.shrinkRetainingCapacity(self.start);
        state.handle_scope_start = self.previous_start;
        state.open_handle_scopes -= 1;
        self.* = undefined;
    }

    /// Takes `handle`, a handle or a `Value` holding one, out of every open scope and returns it;
    /// the caller deinits it.
    pub fn keep(self: *const HandleScope, handle: anytype) @TypeOf(handle) {
        const T = @TypeOf(handle);
        if (T == Value) {
            switch (handle) {
                .table => |h| forgetScopedRoot(self.state, h.ref.index),
                .function => |h| forgetScopedRoot(self.state, h.ref.index),
                .coroutine => |h| forgetScopedRoot(self.state, h.ref.index),
                .userdata => |h| forgetScopedRoot(self.state, h.ref.index),
                else => {},
            }
        } else if (T == Ref) {
            forgetScopedRoot(self.state, handle.index);
        } else {
            forgetScopedRoot(self.state, handle.ref.index);
        }
        return handle;
    }
};

const released_root = std.math.maxInt(usize);

pub fn beginScope(state: *State) HandleScope {
    const scope: HandleScope = .{
        .state = state,
        .generation = state.generation,
        .start = state.scoped_roots.items.len,
        .previous_start = state.handle_scope_start,
    };
    state.handle_scope_start = scope.start;
    state.open_handle_scopes += 1;
    return scope;
}

fn forgetScopedRoot(state: *State, index: usize) void {
    if (state.open_handle_scopes == 0) return;
    const roots = state.scoped_roots.items;
    var at = roots.len;
    while (at > 0) {
        at -= 1;
        if (roots[at] == index) {
            roots[at] = released_root;
            break;
        }
    }
    while (state.scoped_roots.items.len > state.handle_scope_start and state.scoped_roots.getLast() == released_root) {
        _ = state.scoped_roots.pop();
    }
}

pub fn fromRuntime(state: *State, raw: runtime.Value) !Ref {
    const index = try state.raw_state.rootValue(raw);
    if (state.open_handle_scopes != 0) {
        errdefer state.raw_state.unrootValue(index);
        try state.scoped_roots.append(state.allocator(), index);
    }
    return .{ .state = state, .generation = state.generation, .index = index };
}

pub fn validate(ref: Ref, state: *State) !void {
    if (ref.state != state or ref.generation != state.generation) return error.InvalidHandle;
}

pub fn rawValue(ref: Ref) !runtime.Value {
    try validate(ref, ref.state);
    callbacks.bindDispatch(ref.state);
    return ref.state.raw_state.rootedValue(ref.index);
}
