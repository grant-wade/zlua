const std = @import("std");
const zlua = @import("zlua");

fn add(a: i64, b: i64) i64 {
    return a + b;
}

pub fn main(init: std.process.Init) !void {
    const lua = try zlua.State.init(init.gpa, .{
        .limits = .{ .max_instructions = 1_000_000 },
    });
    defer lua.deinit();

    try lua.setGlobals(.{
        .add = add,
        .greeting = "hello",
    });

    try lua.doString(
        \\function greet(name)
        \\  return greeting .. ", " .. name .. "! 2 + 3 = " .. add(2, 3)
        \\end
    , .{ .name = "=readme" });

    var greet = try lua.getGlobal("greet", zlua.Function);
    defer greet.deinit();
    var message = try greet.call(.{"zlua"}, zlua.String);
    defer message.deinit();
    std.debug.print("{f}\n", .{message});
}
