const std = @import("std");
const zlua = @import("zlua");

const Weapon = struct {
    name: []const u8 = "",
    kind: Kind = .sword,
    might: i32 = 0,
    tags: []const []const u8 = &.{},

    const Kind = enum { sword, spear, bow };

    pub const lua = .{ .name = .{ .required = true } };
};

fn report(weapon: Weapon) Weapon.Kind {
    std.debug.print("{s}: might {d}, {d} tags\n", .{ weapon.name, weapon.might, weapon.tags.len });
    return weapon.kind;
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString("return { name = 'pike', kind = 'spear', might = 7, tags = { 'long' } }", .{ .name = "=config" });
    defer chunk.deinit();
    var value = try chunk.call(.{}, zlua.Value);
    defer value.deinit();

    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var diagnostic: zlua.Diagnostic = .{ .gpa = allocator };
    defer diagnostic.deinit();
    const weapon = zlua.decode(Weapon, value, .{ .allocator = arena.allocator(), .diagnostic = &diagnostic }) catch |err| switch (err) {
        error.Invalid => {
            std.debug.print("bad config: {s}\n", .{diagnostic.text});
            return err;
        },
        else => return err,
    };
    _ = report(weapon);

    var report_fn = try lua.newTypedFunction("report", report);
    defer report_fn.deinit();
    try lua.setGlobal("report", report_fn);
    var checked = try lua.loadString(
        \\report({ name = "bow", kind = "bow" })
        \\return pcall(report, { kind = "bow", might = 1.5 })
    , .{ .name = "=checked" });
    defer checked.deinit();
    const accepted, var reason = try checked.call(.{}, struct { bool, zlua.String });
    defer reason.deinit();
    std.debug.print("accepted: {}, {f}\n", .{ accepted, reason });
}
