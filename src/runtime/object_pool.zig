const std = @import("std");

/// Serves allocations of up to `max_size` bytes from size-class free lists in parent-allocated blocks.
pub const ObjectPool = struct {
    parent: std.mem.Allocator,
    free_lists: [class_count]?*FreeSlot = @splat(null),
    /// Unused tail of the newest block.
    cursor: [*]align(granularity) u8 = undefined,
    remaining: usize = 0,
    blocks: ?*Block = null,
    next_block_size: usize = min_block_size,
    /// Bytes handed out and not yet freed, rounded to their size class.
    live_bytes: usize = 0,

    pub const max_size = 128;
    const granularity = 8;
    const class_count = max_size / granularity;
    const min_block_size = 4096;
    const max_block_size = 256 * 1024;

    const FreeSlot = struct {
        next: ?*FreeSlot,
    };

    /// Header at the start of each block.
    const Block = struct {
        next: ?*Block,
        len: usize,
    };

    pub fn create(parent: std.mem.Allocator) !*ObjectPool {
        const pool = try parent.create(ObjectPool);
        pool.* = .{ .parent = parent };
        return pool;
    }

    /// Frees every block; all pooled allocations must already be freed.
    pub fn destroy(self: *ObjectPool) void {
        std.debug.assert(self.live_bytes == 0);
        var block = self.blocks;
        while (block) |current| {
            block = current.next;
            const memory: [*]align(granularity) u8 = @ptrCast(@alignCast(current));
            self.parent.free(memory[0..current.len]);
        }
        const parent = self.parent;
        parent.destroy(self);
    }

    pub fn allocator(self: *ObjectPool) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    inline fn pooled(len: usize, alignment: std.mem.Alignment) bool {
        return len <= max_size and alignment.toByteUnits() <= granularity;
    }

    inline fn classOf(len: usize) usize {
        return (len -| 1) / granularity;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *ObjectPool = @ptrCast(@alignCast(ctx));
        if (!pooled(len, alignment)) return self.parent.rawAlloc(len, alignment, ret_addr);
        const class = classOf(len);
        const size = (class + 1) * granularity;
        if (self.free_lists[class]) |slot| {
            self.free_lists[class] = slot.next;
            self.live_bytes += size;
            return @ptrCast(@alignCast(slot));
        }
        if (self.remaining < size and !self.addBlock()) return null;
        const result = self.cursor;
        self.cursor = @alignCast(self.cursor + size);
        self.remaining -= size;
        self.live_bytes += size;
        return result;
    }

    fn addBlock(self: *ObjectPool) bool {
        const len = self.next_block_size;
        const memory = self.parent.alignedAlloc(u8, .fromByteUnits(granularity), len) catch return false;
        const block: *Block = @ptrCast(@alignCast(memory.ptr));
        block.* = .{ .next = self.blocks, .len = len };
        self.blocks = block;
        self.cursor = memory.ptr + @sizeOf(Block);
        self.remaining = len - @sizeOf(Block);
        self.next_block_size = @min(len * 2, max_block_size);
        return true;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *ObjectPool = @ptrCast(@alignCast(ctx));
        const old_pooled = pooled(memory.len, alignment);
        if (old_pooled != pooled(new_len, alignment)) return false;
        if (old_pooled) return classOf(memory.len) == classOf(new_len);
        return self.parent.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *ObjectPool = @ptrCast(@alignCast(ctx));
        const old_pooled = pooled(memory.len, alignment);
        if (old_pooled != pooled(new_len, alignment)) return null;
        if (old_pooled) return if (classOf(memory.len) == classOf(new_len)) memory.ptr else null;
        return self.parent.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *ObjectPool = @ptrCast(@alignCast(ctx));
        if (!pooled(memory.len, alignment)) return self.parent.rawFree(memory, alignment, ret_addr);
        const class = classOf(memory.len);
        const size = (class + 1) * granularity;
        if (std.debug.runtime_safety) {
            std.debug.assert(self.owns(memory.ptr));
            @memset(memory.ptr[0..size], undefined);
        }
        const slot: *FreeSlot = @ptrCast(@alignCast(memory.ptr));
        slot.* = .{ .next = self.free_lists[class] };
        self.free_lists[class] = slot;
        self.live_bytes -= size;
    }

    fn owns(self: *const ObjectPool, ptr: [*]u8) bool {
        var block = self.blocks;
        while (block) |current| : (block = current.next) {
            const start = @intFromPtr(current);
            if (@intFromPtr(ptr) >= start + @sizeOf(Block) and @intFromPtr(ptr) < start + current.len) return true;
        }
        return false;
    }
};

test "pooled allocations reuse their size class" {
    const pool = try ObjectPool.create(std.testing.allocator);
    defer pool.destroy();
    const a = pool.allocator();
    const first = try a.alloc(u8, 100);
    a.free(first);
    const second = try a.alloc(u8, 97);
    try std.testing.expectEqual(first.ptr, second.ptr);
    const large = try a.alloc(u8, ObjectPool.max_size + 1);
    try std.testing.expect(!pool.owns(large.ptr));
    a.free(large);
    a.free(second);
}
