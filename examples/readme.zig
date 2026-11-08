const std = @import("std");
const zlua = @import("zlua");

fn add(a: i64, b: i64) i64 {
    return a + b;
}

pub fn main(init: std.process.Init) !void {
    var lua = try zlua.State.init(init.gpa, .{
        .limits = .{ .max_instructions = 1_000_000 },
    });
    defer lua.deinit();

    var add_fn = try lua.registerTyped("add", add);
    defer add_fn.deinit();
    try lua.setGlobal("add", add_fn);

    try lua.doString(
        \\function greet(name)
        \\  return "hello, " .. name .. "! 2 + 3 = " .. add(2, 3)
        \\end
    , .{ .name = "=readme" });

    var greet = try lua.getGlobal("greet", zlua.Function);
    defer greet.deinit();
    const message = try greet.call(.{"zlua"}, []const u8);
    std.debug.print("{s}\n", .{message});
}
