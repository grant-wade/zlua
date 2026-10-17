const std = @import("std");
const runtime_types = @import("../runtime/types.zig");

pub const MemoryLimitAllocator = struct {
    lifetime: runtime_types.AllocatorLifetime = .{ .destroy = destroyLifetime },

    parent: std.mem.Allocator,
    limit: usize,
    // Only the owner allocates and changes limit/exceeded, but shared payloads may free
    // concurrently. Relaxed ordering suffices: lifetime release publishes object contents.
    used: std.atomic.Value(usize) = .init(0),
    exceeded: bool = false,

    fn destroyLifetime(lifetime: *runtime_types.AllocatorLifetime) void {
        const self: *MemoryLimitAllocator = @fieldParentPtr("lifetime", lifetime);
        self.parent.destroy(self);
    }

    pub fn init(parent: std.mem.Allocator, limit: usize) MemoryLimitAllocator {
        return .{ .parent = parent, .limit = limit };
    }

    pub fn allocator(self: *MemoryLimitAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn canGrow(self: *const MemoryLimitAllocator, amount: usize) bool {
        return amount <= self.limit -| self.used.load(.monotonic);
    }

    fn deny(self: *MemoryLimitAllocator) ?[*]u8 {
        self.exceeded = true;
        return null;
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *MemoryLimitAllocator = @ptrCast(@alignCast(ctx));
        if (!self.canGrow(len)) return self.deny();
        const ptr = self.parent.rawAlloc(len, alignment, ret_addr) orelse return null;
        _ = self.used.fetchAdd(len, .monotonic);
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *MemoryLimitAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len and !self.canGrow(new_len - memory.len)) {
            self.exceeded = true;
            return false;
        }
        if (!self.parent.rawResize(memory, alignment, new_len, ret_addr)) return false;
        if (new_len > memory.len) {
            _ = self.used.fetchAdd(new_len - memory.len, .monotonic);
        } else {
            _ = self.used.fetchSub(memory.len - new_len, .monotonic);
        }
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *MemoryLimitAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len and !self.canGrow(new_len - memory.len)) return self.deny();
        const ptr = self.parent.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        if (new_len > memory.len) {
            _ = self.used.fetchAdd(new_len - memory.len, .monotonic);
        } else {
            _ = self.used.fetchSub(memory.len - new_len, .monotonic);
        }
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *MemoryLimitAllocator = @ptrCast(@alignCast(ctx));
        _ = self.used.fetchSub(memory.len, .monotonic);
        self.parent.rawFree(memory, alignment, ret_addr);
    }
};

test "retained allocator accounts for concurrent shared frees while owner allocates" {
    if (@import("builtin").single_threaded or @import("builtin").target.cpu.arch.isWasm()) return error.SkipZigTest;
    const Worker = struct {
        allocator: std.mem.Allocator,
        blocks: [128][]u8,
        start: *std.atomic.Value(bool),
        fn run(self: *@This()) void {
            while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
            for (self.blocks) |block| self.allocator.free(block);
        }
    };
    var limit = MemoryLimitAllocator.init(std.testing.allocator, 1024 * 1024);
    const allocator = limit.allocator();
    var start: std.atomic.Value(bool) = .init(false);
    var workers: [4]Worker = undefined;
    var allocated: usize = 0;
    errdefer for (0..allocated) |i| allocator.free(workers[i / 128].blocks[i % 128]);
    for (&workers) |*worker| {
        worker.allocator = allocator;
        worker.start = &start;
        for (&worker.blocks) |*block| {
            block.* = try allocator.alloc(u8, 64);
            allocated += 1;
        }
    }
    var threads: [4]std.Thread = undefined;
    var spawned: usize = 0;
    var joined = false;
    defer if (!joined) {
        start.store(true, .release);
        for (threads[0..spawned]) |thread| thread.join();
        for (workers[spawned..]) |worker| for (worker.blocks) |block| allocator.free(block);
    };
    allocated = 0; // cleanup ownership transferred to workers/defer
    for (&threads, &workers) |*thread, *worker| {
        thread.* = try std.Thread.spawn(.{}, Worker.run, .{worker});
        spawned += 1;
    }
    start.store(true, .release);
    for (0..512) |_| {
        var block = try allocator.alloc(u8, 32);
        block = allocator.realloc(block, 96) catch |err| {
            allocator.free(block);
            return err;
        };
        allocator.free(block);
    }
    for (threads) |thread| thread.join();
    joined = true;
    try std.testing.expectEqual(@as(usize, 0), limit.used.load(.monotonic));
    try std.testing.expect(!limit.exceeded);
}
