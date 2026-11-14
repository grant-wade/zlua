const std = @import("std");
const zlua = @import("zlua");

const Buffer = struct {
    bytes: std.ArrayList(u8) = .empty,

    pub const lua_userdata = .{ .name = "Buffer" };

    pub const lua = .{
        .deinit = .{ .skip = true },
        .length = .{ .key = "__len" },
    };

    pub fn append(self: *Buffer, ctx: *zlua.Context, text: []const u8) !void {
        try self.bytes.appendSlice(ctx.state().allocator(), text);
    }

    pub fn length(self: *const Buffer) i64 {
        return @intCast(self.bytes.items.len);
    }

    pub fn deinit(self: *Buffer, gpa: std.mem.Allocator) void {
        self.bytes.deinit(gpa);
    }
};

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var log: Buffer = .{};
    defer log.deinit(lua.allocator());
    var shared = try lua.wrapUserdata(Buffer, &log, .{});
    defer shared.deinit();
    try lua.setGlobal("log", shared);

    var scratch = try lua.newUserdata(Buffer, .{}, .{ .finalizer = Buffer.deinit });
    defer scratch.deinit();
    try lua.setGlobal("scratch", scratch);

    try lua.doString(
        \\scratch:append('draft')
        \\log:append('scratch holds ' .. #scratch .. ' bytes')
        \\assert(tostring(log):find('^Buffer: '))
        \\assert(log.deinit == nil)
    , .{ .name = "=userdata_options" });

    std.debug.print("{s}\n", .{log.bytes.items});
}
