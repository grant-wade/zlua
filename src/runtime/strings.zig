const std = @import("std");
const static_strings = @import("../stdlib/static_strings.zig");
const State = @import("state.zig").State;
const types = @import("types.zig");
const value_mod = @import("value.zig");

const StringAllocation = types.StringAllocation;

/// Longer strings are allocated without interning, as in Lua.
pub const short_string_limit = 40;

pub const InternMap = std.HashMap([]const u8, []const u8, InternContext, std.hash_map.default_max_load_percentage);

const InternContext = struct {
    pub fn hash(_: InternContext, key: []const u8) u64 {
        return value_mod.hashString(key);
    }

    pub fn eql(_: InternContext, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.eql(u8, lhs, rhs);
    }
};

const Prehashed = struct {
    hash_value: u64,

    pub fn hash(self: Prehashed, _: []const u8) u64 {
        return self.hash_value;
    }

    pub fn eql(_: Prehashed, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.eql(u8, lhs, rhs);
    }
};

/// String interning. The table holds strings weakly; the collector removes entries it frees.
pub const Strings = struct {
    map: InternMap,

    fn parentState(strings: *Strings) *State {
        return @alignCast(@fieldParentPtr("strings", strings));
    }

    pub fn intern(strings: *Strings, bytes: []const u8) ![]const u8 {
        if (bytes.len > short_string_limit) return strings.allocate(bytes);
        return strings.internConstant(bytes);
    }

    /// Interns at any length: identical literals share one string, as with Lua's parser.
    pub fn internConstant(strings: *Strings, bytes: []const u8) ![]const u8 {
        const hash = value_mod.hashString(bytes);
        if (static_strings.canonicalHashed(bytes, hash)) |static| return static;
        const context = Prehashed{ .hash_value = hash };
        if (strings.map.getAdapted(bytes, context)) |interned| {
            // Reuse during sweeping must resurrect the string.
            const state = strings.parentState();
            if (state.gc.phase != .pause) state.gc.markString(interned);
            return interned;
        }
        const interned = try strings.allocate(bytes);
        // Allocation can detach the map for a snapshot, so reserve only now.
        const entry = try strings.map.getOrPutAdapted(interned, context);
        entry.key_ptr.* = interned;
        entry.value_ptr.* = interned;
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
