const std = @import("std");
const static_strings = @import("../stdlib/static_strings.zig");
const State = @import("state.zig").State;
const table_index = @import("table_index.zig");
const types = @import("types.zig");

const String = types.String;

/// Longer strings are allocated without interning, as in Lua.
pub const short_string_limit = String.short_limit;

/// Open-addressed set of interned strings, seeded with the static catalog.
pub const InternSet = struct {
    hashes: []u32 = &.{},
    entries: []?*const String = &.{},
    count: usize = 0,

    const static_capacity = std.math.ceilPowerOfTwoAssert(usize, static_strings.strings.len * 2);
    const StaticImage = struct {
        hashes: [static_capacity]u32,
        entries: [static_capacity]?*const String,
    };
    const static_image: StaticImage = blk: {
        @setEvalBranchQuota(1_000_000);
        var image: StaticImage = .{ .hashes = @splat(0), .entries = @splat(null) };
        for (static_strings.strings) |string| {
            var position = string.hash & (static_capacity - 1);
            while (image.entries[position] != null) position = (position + 1) & (static_capacity - 1);
            image.hashes[position] = string.hash;
            image.entries[position] = string;
        }
        break :blk image;
    };

    /// `extra` is the number of strings to reserve beyond the static catalog.
    pub fn initStatic(allocator: std.mem.Allocator, extra: usize) !InternSet {
        var set = InternSet{};
        set.hashes = try allocator.dupe(u32, &static_image.hashes);
        errdefer allocator.free(set.hashes);
        set.entries = try allocator.dupe(?*const String, &static_image.entries);
        set.count = static_strings.strings.len;
        errdefer set.deinit(allocator);
        try set.ensureUnusedCapacity(allocator, extra);
        return set;
    }

    pub fn deinit(self: *InternSet, allocator: std.mem.Allocator) void {
        allocator.free(self.hashes);
        allocator.free(self.entries);
        self.* = .{};
    }

    pub fn clone(self: *const InternSet, allocator: std.mem.Allocator) !InternSet {
        const hashes = try allocator.dupe(u32, self.hashes);
        errdefer allocator.free(hashes);
        return .{ .hashes = hashes, .entries = try allocator.dupe(?*const String, self.entries), .count = self.count };
    }

    pub inline fn find(self: *const InternSet, bytes: []const u8, hash: u32) ?*const String {
        if (self.entries.len == 0) return null;
        const mask = self.entries.len - 1;
        var position = hash & mask;
        while (self.entries[position]) |string| : (position = (position + 1) & mask) {
            if (self.hashes[position] == hash and string.eqlBytes(bytes)) return string;
        }
        return null;
    }

    pub fn ensureUnusedCapacity(self: *InternSet, allocator: std.mem.Allocator, extra: usize) !void {
        const needed = self.count + extra;
        if (needed + needed / 3 <= self.entries.len) return;
        const capacity = std.math.ceilPowerOfTwoAssert(usize, @max(16, needed * 2));
        const hashes = try allocator.alloc(u32, capacity);
        errdefer allocator.free(hashes);
        const entries = try allocator.alloc(?*const String, capacity);
        @memset(entries, null);
        const old_hashes = self.hashes;
        const old_entries = self.entries;
        self.hashes = hashes;
        self.entries = entries;
        for (old_hashes, old_entries) |hash, entry| if (entry) |string| self.place(string, hash);
        allocator.free(old_hashes);
        allocator.free(old_entries);
    }

    /// The string must be absent and capacity reserved.
    pub fn insertAssumeCapacity(self: *InternSet, string: *const String) void {
        std.debug.assert(self.count + 1 + (self.count + 1) / 3 <= self.entries.len);
        self.place(string, string.hash);
        self.count += 1;
    }

    fn place(self: *InternSet, string: *const String, hash: u32) void {
        const mask = self.entries.len - 1;
        var position = hash & mask;
        while (self.entries[position] != null) position = (position + 1) & mask;
        self.hashes[position] = hash;
        self.entries[position] = string;
    }

    pub fn remove(self: *InternSet, string: *const String) void {
        const mask = self.entries.len - 1;
        var hole = string.hash & mask;
        while (self.entries[hole] != string) hole = (hole + 1) & mask;
        var next = (hole + 1) & mask;
        while (self.entries[next] != null) : (next = (next + 1) & mask) {
            const home = self.hashes[next] & mask;
            if (((next -% home) & mask) >= ((next -% hole) & mask)) {
                self.hashes[hole] = self.hashes[next];
                self.entries[hole] = self.entries[next];
                hole = next;
            }
        }
        self.entries[hole] = null;
        self.count -= 1;
    }
};

/// String interning. The set holds strings weakly; the collector removes entries it frees.
pub const Strings = struct {
    set: InternSet = .{},
    /// `Builder` storage, empty while a builder holds it.
    scratch: std.ArrayList(u8) = .empty,

    fn parentState(strings: *Strings) *State {
        return @alignCast(@fieldParentPtr("strings", strings));
    }

    pub fn deinit(strings: *Strings, allocator: std.mem.Allocator) void {
        strings.set.deinit(allocator);
        strings.scratch.deinit(allocator);
    }

    pub fn intern(strings: *Strings, bytes: []const u8) !*const String {
        if (bytes.len > short_string_limit) return strings.allocate(bytes);
        return strings.internConstant(bytes);
    }

    /// Interns at any length: identical literals share one string, as with Lua's parser.
    pub fn internConstant(strings: *Strings, bytes: []const u8) !*const String {
        const hash = table_index.hashStringKey(bytes);
        if (strings.set.find(bytes, hash)) |interned| {
            // Reuse during sweeping must resurrect the string.
            const state = strings.parentState();
            if (state.gc.phase != .pause) state.gc.markString(interned);
            return interned;
        }
        const string = try strings.create(bytes.len);
        @memcpy(string.bytesMut(), bytes);
        string.hash = hash;
        string.hashed = true;
        // Allocation can detach the set for a snapshot, so reserve only now.
        const state = strings.parentState();
        try strings.set.ensureUnusedCapacity(state.allocator, 1);
        string.interned = true;
        strings.set.insertAssumeCapacity(string);
        return string;
    }

    /// Copies `bytes` into a new collectable string without interning it.
    pub fn allocate(strings: *Strings, bytes: []const u8) !*const String {
        const string = try strings.createLong(bytes.len);
        @memcpy(string.bytesMut(), bytes);
        return string;
    }

    pub fn createLong(strings: *Strings, len: usize) !*String {
        std.debug.assert(len > short_string_limit);
        return strings.create(len);
    }

    pub fn concat(strings: *Strings, left: []const u8, right: []const u8) !*const String {
        const len = left.len + right.len;
        if (len <= short_string_limit) {
            var buffer: [short_string_limit]u8 = undefined;
            @memcpy(buffer[0..left.len], left);
            @memcpy(buffer[left.len..len], right);
            return strings.internConstant(buffer[0..len]);
        }
        const string = try strings.createLong(len);
        @memcpy(string.bytesMut()[0..left.len], left);
        @memcpy(string.bytesMut()[left.len..], right);
        return string;
    }

    pub fn duplicate(strings: *Strings, source: *const String) !*const String {
        const state = strings.parentState();
        const string = try strings.create(source.len);
        @memcpy(string.bytesMut(), source.bytes());
        string.hash = source.hash;
        string.hashed = source.hashed;
        if (source.interned) {
            try strings.set.ensureUnusedCapacity(state.allocator, 1);
            string.interned = true;
            strings.set.insertAssumeCapacity(string);
        }
        return string;
    }

    fn create(strings: *Strings, len: usize) !*String {
        const state = strings.parentState();
        const size = std.math.add(usize, @sizeOf(String), len) catch return error.OutOfMemory;
        const memory = try state.objects().alignedAlloc(u8, .of(String), size);
        errdefer state.objects().free(memory);
        const string: *String = @ptrCast(memory.ptr);
        string.* = .{ .len = len };
        try state.registerAllocation("string_allocations", string);
        state.gc.noteAllocation(string.gcBytes());
        return string;
    }

    pub fn builder(strings: *Strings) Builder {
        var buffer = strings.scratch;
        strings.scratch = .empty;
        buffer.clearRetainingCapacity();
        return .{ .strings = strings, .buffer = buffer };
    }
};

pub fn destroy(allocator: std.mem.Allocator, string: *const String) void {
    const memory: [*]align(@alignOf(String)) const u8 = @ptrCast(string);
    allocator.free(memory[0 .. @sizeOf(String) + string.len]);
}

/// Accumulates bytes for one new string, like `luaL_Buffer`.
pub const Builder = struct {
    const max_retained = 16 * 1024;

    strings: *Strings,
    buffer: std.ArrayList(u8),

    pub fn deinit(self: *Builder) void {
        const a = self.allocator();
        if (self.buffer.capacity <= max_retained and self.strings.scratch.capacity < self.buffer.capacity) {
            self.strings.scratch.deinit(a);
            self.strings.scratch = self.buffer;
        } else self.buffer.deinit(a);
        self.buffer = .empty;
    }

    pub fn allocator(self: *const Builder) std.mem.Allocator {
        return self.strings.parentState().allocator;
    }

    pub fn append(self: *Builder, byte: u8) !void {
        try self.buffer.append(self.allocator(), byte);
    }

    pub fn appendSlice(self: *Builder, bytes: []const u8) !void {
        try self.buffer.appendSlice(self.allocator(), bytes);
    }

    pub fn appendNTimes(self: *Builder, byte: u8, count: usize) !void {
        try self.buffer.appendNTimes(self.allocator(), byte, count);
    }

    pub fn print(self: *Builder, comptime fmt: []const u8, args: anytype) !void {
        try self.buffer.print(self.allocator(), fmt, args);
    }

    pub fn finish(self: *Builder) !*const String {
        defer self.deinit();
        return self.strings.intern(self.buffer.items);
    }
};
