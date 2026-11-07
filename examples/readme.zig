const std = @import("std");
const zlua = @import("zlua");

const Alert = struct {
    name: []const u8,
    limit: i64 = 100,
    tags: []const []const u8 = &.{},
};

fn clamp(value: i64, min: i64, max: i64) i64 {
    return @min(@max(value, min), max);
}

const plugin =
    \\local plugin = {
    \\  alert = { name = "disk", limit = clamp(250, 0, 90), tags = { "ops" } },
    \\}
    \\
    \\function plugin.check(used)
    \\  if used < 0 then while true do end end
    \\  return used > plugin.alert.limit
    \\end
    \\
    \\return plugin
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var lua = try zlua.State.init(gpa, .{ .limits = zlua.Limits.untrusted });
    defer lua.deinit();

    var clamp_fn = try lua.registerTyped("clamp", clamp);
    defer clamp_fn.deinit();
    try lua.setGlobal("clamp", clamp_fn);

    var chunk = try lua.loadString(plugin, .{ .name = "=plugin" });
    defer chunk.deinit();
    var module = try chunk.call(.{}, zlua.Table);
    defer module.deinit();

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var diagnostic: zlua.Diagnostic = .{ .gpa = gpa };
    defer diagnostic.deinit();
    var alert_value = try module.get("alert", zlua.Value);
    defer alert_value.deinit();
    const alert = try zlua.decode(Alert, alert_value, .{
        .allocator = arena.allocator(),
        .diagnostic = &diagnostic,
    });

    var check = try module.get("check", zlua.Function);
    defer check.deinit();
    const over = try check.call(.{95}, bool);
    std.debug.print("{s} limit={d} tags={d} over={}\n", .{ alert.name, alert.limit, alert.tags.len, over });

    switch (try check.protectedCallWith(.{-1}, bool, .{ .max_instructions = 10_000 })) {
        .ok => unreachable,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            const message = try err.message();
            defer gpa.free(message);
            std.debug.print("stopped: {s}\n", .{message});
        },
    }
}
