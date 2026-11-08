const std = @import("std");

pub const name = "inventory";

pub const Item = struct {
    count: i64,

    pub fn add(self: *Item, amount: i64) i64 {
        self.count += amount;
        return self.count;
    }
};

pub fn total(counts: []const i64) i64 {
    var sum: i64 = 0;
    for (counts) |count| sum += count;
    return sum;
}

pub fn label(allocator: std.mem.Allocator, count: i64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d} items", .{count});
}

pub const lua = .{ .label = .{ .skip = true } };
