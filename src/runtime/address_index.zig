const std = @import("std");

/// Map from nonzero object addresses to registry positions. Linear probing with
/// backward-shift deletion keeps probe chains short under constant allocation churn.
pub const AddressIndex = struct {
    keys: []usize = &.{},
    values: []usize = &.{},
    len: usize = 0,
    shift: u6 = 63,

    pub const empty: AddressIndex = .{};

    pub fn deinit(self: *AddressIndex, allocator: std.mem.Allocator) void {
        allocator.free(self.keys);
        allocator.free(self.values);
        self.* = .{};
    }

    pub fn clone(self: *const AddressIndex, allocator: std.mem.Allocator) !AddressIndex {
        const keys = try allocator.dupe(usize, self.keys);
        errdefer allocator.free(keys);
        return .{ .keys = keys, .values = try allocator.dupe(usize, self.values), .len = self.len, .shift = self.shift };
    }

    pub fn count(self: *const AddressIndex) usize {
        return self.len;
    }

    pub fn ensureTotalCapacity(self: *AddressIndex, allocator: std.mem.Allocator, total: usize) !void {
        if (total + total / 2 <= self.keys.len) return;
        const slot_count = std.math.ceilPowerOfTwoAssert(usize, @max(16, total * 2));
        const keys = try allocator.alloc(usize, slot_count);
        errdefer allocator.free(keys);
        const values = try allocator.alloc(usize, slot_count);
        @memset(keys, 0);
        const old_keys = self.keys;
        const old_values = self.values;
        self.keys = keys;
        self.values = values;
        self.shift = @intCast(@as(u7, 64) - std.math.log2_int(usize, slot_count));
        for (old_keys, old_values) |key, value| if (key != 0) self.place(key, value);
        allocator.free(old_keys);
        allocator.free(old_values);
    }

    pub fn ensureUnusedCapacity(self: *AddressIndex, allocator: std.mem.Allocator, extra: usize) !void {
        return self.ensureTotalCapacity(allocator, self.len + extra);
    }

    pub fn put(self: *AddressIndex, allocator: std.mem.Allocator, key: usize, value: usize) !void {
        try self.ensureUnusedCapacity(allocator, 1);
        self.putAssumeCapacity(key, value);
    }

    pub fn putAssumeCapacity(self: *AddressIndex, key: usize, value: usize) void {
        std.debug.assert(key != 0);
        if (self.getPtr(key)) |slot| {
            slot.* = value;
            return;
        }
        std.debug.assert(self.len + 1 + (self.len + 1) / 2 <= self.keys.len);
        self.place(key, value);
        self.len += 1;
    }

    pub fn get(self: *const AddressIndex, key: usize) ?usize {
        const position = self.find(key) orelse return null;
        return self.values[position];
    }

    pub fn getPtr(self: *const AddressIndex, key: usize) ?*usize {
        const position = self.find(key) orelse return null;
        return &self.values[position];
    }

    pub fn contains(self: *const AddressIndex, key: usize) bool {
        return self.find(key) != null;
    }

    pub fn remove(self: *AddressIndex, key: usize) bool {
        var hole = self.find(key) orelse return false;
        const mask = self.keys.len - 1;
        var position = hole;
        while (true) {
            position = (position + 1) & mask;
            const moved = self.keys[position];
            if (moved == 0) break;
            const ideal = self.home(moved);
            // Move back only entries whose home is not cyclically within (hole, position].
            if ((position -% ideal) & mask >= (position -% hole) & mask) {
                self.keys[hole] = moved;
                self.values[hole] = self.values[position];
                hole = position;
            }
        }
        self.keys[hole] = 0;
        self.len -= 1;
        return true;
    }

    inline fn home(self: *const AddressIndex, key: usize) usize {
        return @intCast((@as(u64, key) *% 0x9e3779b97f4a7c15) >> self.shift);
    }

    inline fn find(self: *const AddressIndex, key: usize) ?usize {
        if (self.len == 0) return null;
        const mask = self.keys.len - 1;
        var position = self.home(key);
        while (true) : (position = (position + 1) & mask) {
            const stored = self.keys[position];
            if (stored == key) return position;
            if (stored == 0) return null;
        }
    }

    fn place(self: *AddressIndex, key: usize, value: usize) void {
        const mask = self.keys.len - 1;
        var position = self.home(key);
        while (self.keys[position] != 0) position = (position + 1) & mask;
        self.keys[position] = key;
        self.values[position] = value;
    }
};

test "address index survives churn" {
    const allocator = std.testing.allocator;
    var index: AddressIndex = .empty;
    defer index.deinit(allocator);
    var live: std.AutoHashMapUnmanaged(usize, usize) = .empty;
    defer live.deinit(allocator);
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();
    for (0..20000) |step| {
        const key = (random.uintLessThan(usize, 600) + 1) * 16;
        if (random.boolean()) {
            try index.put(allocator, key, step);
            try live.put(allocator, key, step);
        } else {
            try std.testing.expectEqual(live.remove(key), index.remove(key));
        }
        try std.testing.expectEqual(live.count(), index.count());
    }
    var iterator = live.iterator();
    while (iterator.next()) |entry| try std.testing.expectEqual(entry.value_ptr.*, index.get(entry.key_ptr.*).?);
}
