const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const Value = types.Value;
const TableEntry = types.TableEntry;

/// A table's hash part: this header, then `capacity` entries in insertion order, then `slot_count` index slots.
pub const HashPart = struct {
    len: u32 align(@alignOf(TableEntry)) = 0,
    capacity: u32,
    slot_count: u32,
    /// Nonzero after a long probe chain; slot hashes are then keyed with it.
    salt: u32 = 0,

    pub const Slot = struct {
        hash: u32,
        /// Entry position plus one; zero marks an empty slot.
        entry: u32,
    };

    pub const linear_limit = 4;
    const entries_offset = std.mem.alignForward(usize, @sizeOf(HashPart), @alignOf(TableEntry));
    const alignment: std.mem.Alignment = .of(TableEntry);

    pub fn create(allocator: std.mem.Allocator, capacity: u32) !*HashPart {
        const memory = try allocator.alignedAlloc(u8, alignment, allocationBytes(capacity));
        const part: *HashPart = @ptrCast(memory.ptr);
        part.* = .{ .capacity = capacity, .slot_count = slotCountFor(capacity) };
        @memset(part.slots(), .{ .hash = 0, .entry = 0 });
        return part;
    }

    pub fn destroy(self: *HashPart, allocator: std.mem.Allocator) void {
        const memory: [*]align(alignment.toByteUnits()) u8 = @ptrCast(self);
        allocator.free(memory[0..allocationBytes(self.capacity)]);
    }

    pub fn clone(self: *const HashPart, allocator: std.mem.Allocator) !*HashPart {
        const part = try create(allocator, self.capacity);
        const bytes = allocationBytes(self.capacity);
        @memcpy(@as([*]u8, @ptrCast(part))[0..bytes], @as([*]const u8, @ptrCast(self))[0..bytes]);
        return part;
    }

    pub fn allocationBytes(capacity: u32) usize {
        return entries_offset + @as(usize, capacity) * @sizeOf(TableEntry) + @as(usize, slotCountFor(capacity)) * @sizeOf(Slot);
    }

    /// The largest capacity of at least `count` that fits the same power-of-two size and keeps small parts unindexed.
    pub fn capacityFor(count: usize) !u32 {
        var capacity = std.math.cast(u32, @max(count, 1)) orelse return error.OutOfMemory;
        const size = std.math.ceilPowerOfTwo(usize, allocationBytes(capacity)) catch return error.OutOfMemory;
        const limit: u32 = if (capacity <= linear_limit) linear_limit else std.math.maxInt(u32);
        while (capacity < limit and allocationBytes(capacity + 1) <= size) capacity += 1;
        return capacity;
    }

    fn slotCountFor(capacity: u32) u32 {
        if (capacity <= linear_limit) return 0;
        // Load factor at most 3/4.
        return std.math.ceilPowerOfTwoAssert(u32, @max(8, capacity + (capacity + 2) / 3));
    }

    inline fn storage(self: *const HashPart) [*]TableEntry {
        return @ptrCast(@alignCast(@as([*]u8, @ptrCast(@constCast(self))) + entries_offset));
    }

    pub inline fn entries(self: *const HashPart) []TableEntry {
        return self.storage()[0..self.len];
    }

    pub inline fn slots(self: *const HashPart) []Slot {
        const base: [*]Slot = @ptrCast(@alignCast(self.storage() + self.capacity));
        return base[0..self.slot_count];
    }

    pub inline fn find(self: *const HashPart, key: Value) ?usize {
        if (self.slot_count == 0) {
            for (self.entries(), 0..) |entry, index| if (keysEqual(entry.key, key)) return index;
            return null;
        }
        const hash = self.slotHash(key);
        const table_slots = self.slots();
        const mask = table_slots.len - 1;
        var position = hash & mask;
        while (true) : (position = (position + 1) & mask) {
            const slot = table_slots[position];
            if (slot.entry == 0) return null;
            if (slot.hash == hash and keysEqual(self.storage()[slot.entry - 1].key, key)) return slot.entry - 1;
        }
    }

    /// `key_hash` is `hashStringKey(key)`.
    pub inline fn findBytes(self: *const HashPart, key: []const u8, key_hash: u32) ?usize {
        if (self.slot_count == 0) {
            for (self.entries(), 0..) |entry, index| {
                if (entry.key == .string and entry.key.string.eqlBytes(key)) return index;
            }
            return null;
        }
        const hash = slotHashOfBytes(key, key_hash, self.salt);
        const table_slots = self.slots();
        const mask = table_slots.len - 1;
        var position = hash & mask;
        while (true) : (position = (position + 1) & mask) {
            const slot = table_slots[position];
            if (slot.entry == 0) return null;
            if (slot.hash != hash) continue;
            const stored = self.storage()[slot.entry - 1].key;
            if (stored == .string and stored.string.eqlBytes(key)) return slot.entry - 1;
        }
    }

    /// `key` must be absent and `len` below `capacity`.
    pub inline fn appendAssumeCapacity(self: *HashPart, key: Value, value: Value) void {
        std.debug.assert(self.len < self.capacity);
        self.storage()[self.len] = .{ .key = key, .value = value };
        self.len += 1;
        if (self.slot_count != 0 and self.place(.{ .hash = self.slotHash(key), .entry = self.len }) and self.salt == 0) {
            self.salt = newHashSalt(@intFromPtr(self));
            self.reindex();
        }
    }

    /// Restores the index after entries were removed, moved, or copied in.
    pub fn reindex(self: *HashPart) void {
        if (self.slot_count == 0) return;
        @memset(self.slots(), .{ .hash = 0, .entry = 0 });
        for (self.entries(), 1..) |entry, position| {
            if (self.place(.{ .hash = self.slotHash(entry.key), .entry = @intCast(position) }) and self.salt == 0) {
                self.salt = newHashSalt(@intFromPtr(self));
                return self.reindex();
            }
        }
    }

    inline fn slotHash(self: *const HashPart, key: Value) u32 {
        if (self.salt != 0) {
            @branchHint(.cold);
            return keyedKey(key, self.salt);
        }
        return hashKey(key);
    }

    /// Returns true when the probe chain was long.
    fn place(self: *HashPart, slot: Slot) bool {
        const table_slots = self.slots();
        const mask = table_slots.len - 1;
        var position = slot.hash & mask;
        var chain: ChainLength = .{};
        while (table_slots[position].entry != 0) : (position = (position + 1) & mask) chain.add(table_slots[position].hash == slot.hash);
        table_slots[position] = slot;
        return chain.isLong();
    }
};

/// Probes made placing a key in a table or the intern set.
pub const ChainLength = struct {
    probes: u32 = 0,
    same_hash: u32 = 0,

    pub inline fn add(self: *ChainLength, same_hash: bool) void {
        self.probes += 1;
        self.same_hash += @intFromBool(same_hash);
    }

    /// True when the keys look chosen to collide.
    pub inline fn isLong(self: ChainLength) bool {
        return self.probes > 512 or self.same_hash > 16;
    }
};

const KeyedHash = std.crypto.auth.siphash.SipHash64(1, 3);

var process_key: [KeyedHash.key_length]u8 = undefined;
var process_key_state: std.atomic.Value(enum(u8) { unset, filling, ready }) = .init(.unset);

/// The process's secret hash key; every thread sees the same bytes.
fn processKey() *const [KeyedHash.key_length]u8 {
    if (process_key_state.load(.acquire) == .ready) return &process_key;
    if (process_key_state.cmpxchgStrong(.unset, .filling, .acquire, .acquire) == null) {
        fillProcessKey();
        process_key_state.store(.ready, .release);
    } else {
        while (process_key_state.load(.acquire) != .ready) std.atomic.spinLoopHint();
    }
    return &process_key;
}

fn fillProcessKey() void {
    if (builtin.os.tag != .freestanding) {
        const io = std.Io.Threaded.global_single_threaded.io();
        if (io.randomSecure(&process_key)) |_| return else |_| {}
    }
    const addresses = [_]usize{ @frameAddress(), @intFromPtr(&process_key), @returnAddress() };
    const low = std.hash.Wyhash.hash(0, std.mem.asBytes(&addresses));
    const high = std.hash.Wyhash.hash(low, std.mem.asBytes(&addresses));
    std.mem.writeInt(u64, process_key[0..8], low, .little);
    std.mem.writeInt(u64, process_key[8..16], high, .little);
}

/// A nonzero per-index key a script can't predict. `seed` distinguishes indexes.
pub fn newHashSalt(seed: usize) u32 {
    return @truncate(KeyedHash.toInt(std.mem.asBytes(&seed), processKey()) | 1);
}

/// The slot hash of `bytes`, whose `hashStringKey` is `bytes_hash`, in an index with `salt`.
pub inline fn slotHashOfBytes(bytes: []const u8, bytes_hash: u32, salt: u32) u32 {
    if (salt != 0) {
        @branchHint(.cold);
        return keyedBytes(bytes, salt);
    }
    return bytes_hash;
}

noinline fn keyedBytes(bytes: []const u8, salt: u32) u32 {
    var key = processKey().*;
    std.mem.writeInt(u32, key[0..4], std.mem.readInt(u32, key[0..4], .little) ^ salt, .little);
    return foldHash(KeyedHash.toInt(bytes, &key));
}

noinline fn keyedKey(key: Value, salt: u32) u32 {
    if (key == .string) return keyedBytes(key.string.bytes(), salt);
    const hash = value_mod.hashValue(key);
    return keyedBytes(std.mem.asBytes(&hash), salt);
}

pub inline fn hashKey(key: Value) u32 {
    if (key == .string) return key.string.tableHash();
    return foldHash(value_mod.hashValue(key));
}

pub inline fn foldHash(hash: u64) u32 {
    return @truncate(hash ^ (hash >> 32));
}

pub inline fn hashStringKey(bytes: []const u8) u32 {
    return foldHash(value_mod.hashString(bytes));
}

pub inline fn keysEqual(stored: Value, key: Value) bool {
    if (key == .string) return stored == .string and key.string.eql(stored.string);
    return value_mod.valuesEqual(stored, key);
}
