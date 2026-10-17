const std = @import("std");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const Value = types.Value;
const TableEntry = types.TableEntry;

/// Open-addressed index from hash-part keys to positions in `Table.entries`.
/// Slots keep 32 hash bits so most probes never touch the entry they name.
pub const EntryIndex = struct {
    slots: []Slot = &.{},
    count: usize = 0,

    pub const Slot = struct {
        hash: u32,
        /// Entry position plus one; zero marks an empty slot.
        entry: u32,
    };

    pub fn deinit(self: *EntryIndex, allocator: std.mem.Allocator) void {
        allocator.free(self.slots);
        self.* = .{};
    }

    pub inline fn capacity(self: *const EntryIndex) usize {
        return self.slots.len;
    }

    pub fn clone(self: *const EntryIndex, allocator: std.mem.Allocator) !EntryIndex {
        return .{ .slots = try allocator.dupe(Slot, self.slots), .count = self.count };
    }

    pub fn clearRetainingCapacity(self: *EntryIndex) void {
        @memset(self.slots, .{ .hash = 0, .entry = 0 });
        self.count = 0;
    }

    pub inline fn find(self: *const EntryIndex, entries: []const TableEntry, key: Value, hash: u32) ?usize {
        const mask = self.slots.len - 1;
        var position = hash & mask;
        while (true) : (position = (position + 1) & mask) {
            const slot = self.slots[position];
            if (slot.entry == 0) return null;
            if (slot.hash == hash and keysEqual(entries[slot.entry - 1].key, key)) return slot.entry - 1;
        }
    }

    pub fn ensureTotalCapacity(self: *EntryIndex, allocator: std.mem.Allocator, count: usize) !void {
        const needed = slotCountFor(count);
        if (needed <= self.slots.len) return;
        const old = self.slots;
        const slots = try allocator.alloc(Slot, needed);
        @memset(slots, .{ .hash = 0, .entry = 0 });
        self.slots = slots;
        for (old) |slot| if (slot.entry != 0) self.place(slot);
        allocator.free(old);
    }

    pub inline fn ensureUnusedCapacity(self: *EntryIndex, allocator: std.mem.Allocator, extra: usize) !void {
        return self.ensureTotalCapacity(allocator, self.count + extra);
    }

    /// The key must be absent and capacity reserved.
    pub inline fn insertAssumeCapacity(self: *EntryIndex, hash: u32, entry_index: usize) void {
        std.debug.assert(slotCountFor(self.count + 1) <= self.slots.len);
        self.place(.{ .hash = hash, .entry = @intCast(entry_index + 1) });
        self.count += 1;
    }

    /// Reindexes `entries` from scratch, keeping capacity when it suffices.
    pub fn rebuild(self: *EntryIndex, allocator: std.mem.Allocator, entries: []const TableEntry) !void {
        try self.ensureTotalCapacity(allocator, entries.len);
        self.clearRetainingCapacity();
        for (entries, 0..) |entry, index| self.insertAssumeCapacity(hashKey(entry.key), index);
    }

    fn place(self: *EntryIndex, slot: Slot) void {
        const mask = self.slots.len - 1;
        var position = slot.hash & mask;
        while (self.slots[position].entry != 0) position = (position + 1) & mask;
        self.slots[position] = slot;
    }

    fn slotCountFor(count: usize) usize {
        if (count == 0) return 0;
        // Load factor at most 3/4.
        return std.math.ceilPowerOfTwoAssert(usize, @max(8, count + (count + 2) / 3));
    }
};

pub inline fn hashKey(key: Value) u32 {
    return foldHash(value_mod.hashValue(key));
}

pub inline fn foldHash(hash: u64) u32 {
    return @truncate(hash ^ (hash >> 32));
}

pub inline fn hashStringKey(bytes: []const u8) u32 {
    return foldHash(value_mod.hashString(bytes));
}

pub inline fn keysEqual(stored: Value, key: Value) bool {
    if (key == .string) return stored == .string and stringsEqual(stored.string, key.string);
    return value_mod.valuesEqual(stored, key);
}

pub inline fn stringsEqual(lhs: []const u8, rhs: []const u8) bool {
    return lhs.len == rhs.len and (lhs.ptr == rhs.ptr or std.mem.eql(u8, lhs, rhs));
}
