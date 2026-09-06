const std = @import("std");
const Timestamp = std.Io.Timestamp;
const Metric = @import("results.zig").Metric;

pub const CounterSnapshot = struct {
    allocations: u64,
    resizes: u64,
    requested_bytes: u64,
    live_bytes: u64,
};

pub const CountingAllocator = struct {
    backing: std.mem.Allocator,
    allocations: u64 = 0,
    resizes: u64 = 0,
    requested_bytes: u64 = 0,
    live_bytes: u64 = 0,
    peak_bytes: u64 = 0,
    phase_peak_bytes: u64 = 0,

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn beginPhase(self: *CountingAllocator) CounterSnapshot {
        self.phase_peak_bytes = self.live_bytes;
        return self.snapshot();
    }

    pub fn snapshot(self: *const CountingAllocator) CounterSnapshot {
        return .{
            .allocations = self.allocations,
            .resizes = self.resizes,
            .requested_bytes = self.requested_bytes,
            .live_bytes = self.live_bytes,
        };
    }

    fn accountSize(self: *CountingAllocator, old_len: usize, new_len: usize) void {
        if (new_len >= old_len) {
            const growth = new_len - old_len;
            self.live_bytes += growth;
            self.requested_bytes += growth;
        } else {
            self.live_bytes -= old_len - new_len;
        }
        self.peak_bytes = @max(self.peak_bytes, self.live_bytes);
        self.phase_peak_bytes = @max(self.phase_peak_bytes, self.live_bytes);
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const result = self.backing.rawAlloc(len, alignment, return_address) orelse return null;
        self.allocations += 1;
        self.accountSize(0, len);
        return result;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        if (!self.backing.rawResize(memory, alignment, new_len, return_address)) return false;
        self.resizes += 1;
        self.accountSize(memory.len, new_len);
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const result = self.backing.rawRemap(memory, alignment, new_len, return_address) orelse return null;
        self.resizes += 1;
        self.accountSize(memory.len, new_len);
        return result;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        self.backing.rawFree(memory, alignment, return_address);
        self.live_bytes -= memory.len;
    }
};

pub fn elapsedSince(io: std.Io, start: Timestamp) u64 {
    return @intCast(start.durationTo(Timestamp.now(io, .awake)).toNanoseconds());
}

pub fn phaseMetric(counter: *const CountingAllocator, before: CounterSnapshot, elapsed_ns: u64, runtime_bytes: usize) Metric {
    const after = counter.snapshot();
    return .{
        .elapsed_ns = elapsed_ns,
        .allocations = after.allocations - before.allocations,
        .resizes = after.resizes - before.resizes,
        .requested_bytes = after.requested_bytes - before.requested_bytes,
        .live_bytes = after.live_bytes,
        .peak_bytes = counter.phase_peak_bytes,
        .runtime_bytes = runtime_bytes,
    };
}

test "phase peak includes live storage and resets between phases" {
    var counter: CountingAllocator = .{ .backing = std.testing.allocator };
    const a = counter.allocator();
    const first = try a.alloc(u8, 32);
    const before = counter.beginPhase();
    const second = try a.alloc(u8, 64);
    a.free(first);
    const measured = phaseMetric(&counter, before, 1, 0);
    try std.testing.expectEqual(@as(?u64, 96), measured.peak_bytes);
    try std.testing.expectEqual(@as(?u64, 64), measured.live_bytes);
    try std.testing.expectEqual(@as(?u64, 64), measured.requested_bytes);
    _ = counter.beginPhase();
    try std.testing.expectEqual(@as(u64, 64), counter.phase_peak_bytes);
    a.free(second);
    try std.testing.expectEqual(@as(u64, 0), counter.live_bytes);
}
