const std = @import("std");
const zlua = @import("zlua");

const Counter = struct {
    value: i64,

    pub const lua = .{
        .increment = .{ .key = "inc" },
        .reset = .{ .skip = true },
    };

    pub fn increment(self: *Counter, amount: i64) i64 {
        self.value += amount;
        return self.value;
    }

    pub fn get(self: *const Counter) i64 {
        return self.value;
    }

    pub fn reset(self: *Counter) void {
        self.value = 0;
    }

    pub fn __tostring(self: *const Counter) []const u8 {
        _ = self;
        return "Counter";
    }
};

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdata(Counter, .{ .value = 0 }, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);

    try lua.doString(
        \\assert(counter:inc(2) == 2)
        \\assert(counter:inc(3) == 5)
        \\assert(counter:get() == 5)
        \\assert(counter.increment == nil and counter.reset == nil)
        \\assert(tostring(counter) == 'Counter')
    , .{ .name = "=userdata_counter" });

    const payload = try counter.ptr();
    std.debug.print("counter={d}\n", .{payload.value});

    payload.reset();
    try lua.doString("assert(counter:get() == 0)", .{ .name = "=userdata_counter" });
}
