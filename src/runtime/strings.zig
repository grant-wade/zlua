const std = @import("std");
const static_strings = @import("../stdlib/static_strings.zig");
const State = @import("state.zig").State;
const types = @import("types.zig");

const StringAllocation = types.StringAllocation;

/// String interning. The table holds strings weakly; the collector removes entries it frees.
pub const Strings = struct {
    map: std.StringHashMap([]const u8),

    fn parentState(strings: *Strings) *State {
        return @alignCast(@fieldParentPtr("strings", strings));
    }

    pub fn intern(strings: *Strings, bytes: []const u8) ![]const u8 {
        if (static_strings.canonical(bytes)) |static| return static;
        if (strings.map.get(bytes)) |interned| {
            // Reuse during sweeping must resurrect the string.
            const state = strings.parentState();
            if (state.gc.phase != .pause) state.gc.markString(interned);
            return interned;
        }
        const interned = try strings.allocate(bytes);
        try strings.map.put(interned, interned);
        return interned;
    }

    /// Copies `bytes` into a new collectable string without interning it.
    pub fn allocate(strings: *Strings, bytes: []const u8) ![]const u8 {
        return strings.adopt(try strings.parentState().allocator.dupe(u8, bytes));
    }

    /// Takes ownership of `allocated`, which must come from the state's allocator.
    pub fn adopt(strings: *Strings, allocated: []u8) ![]const u8 {
        const state = strings.parentState();
        errdefer state.allocator.free(allocated);
        try state.registerAllocation("string_allocations", StringAllocation{ .bytes = allocated });
        errdefer {
            const removed = state.string_allocations.pop().?;
            if (state.rollback) |journal| journal.freed(@intFromPtr(removed.bytes.ptr));
        }
        if (allocated.len != 0) try state.string_allocation_index.put(state.allocator, @intFromPtr(allocated.ptr), state.string_allocations.items.len - 1);
        state.gc.noteAllocation(@sizeOf(StringAllocation) + allocated.len);
        return allocated;
    }
};
