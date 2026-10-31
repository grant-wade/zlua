const std = @import("std");
const api = @import("../root.zig");
const a = std.testing.allocator;

const Want = struct { []const u8, usize, enum { read, write } };

fn expectGlobals(source: []const u8, want: []const Want) !void {
    var analysis = try api.analyze(a, source);
    defer analysis.deinit();
    errdefer for (analysis.globals) |use| std.debug.print("{s}:{d} {t}\n", .{ use.name, use.line, use.access });
    try std.testing.expectEqual(want.len, analysis.globals.len);
    for (want, analysis.globals) |w, use| {
        try std.testing.expectEqualStrings(w[0], use.name);
        try std.testing.expectEqual(w[1], use.line);
        try std.testing.expectEqualStrings(@tagName(w[2]), @tagName(use.access));
    }
}

test "analyze lists global reads and writes with their lines" {
    try expectGlobals(
        \\x = y
        \\print(x)
        \\t.field = 1
    , &.{
        .{ "x", 1, .write },
        .{ "y", 1, .read },
        .{ "print", 2, .read },
        .{ "x", 2, .read },
        .{ "t", 3, .read },
    });
}

test "analyze sees globals inside functions and function names" {
    try expectGlobals(
        \\function f()
        \\  return function() return g end
        \\end
        \\function t.a.b() end
        \\function t:m() end
    , &.{
        .{ "f", 1, .write },
        .{ "g", 2, .read },
        .{ "t", 4, .read },
        .{ "t", 5, .read },
    });
}

test "analyze leaves out locals, upvalues and parameters" {
    try expectGlobals(
        \\local a, b = 1, 2
        \\local function f(c) return a + b + c end
        \\for i = 1, 2 do local d = i end
        \\for k in next, {} do local e = k end
    , &.{
        .{ "next", 4, .read },
    });
}

test "analyze leaves out uses under another _ENV" {
    try expectGlobals(
        \\x = 1
        \\do
        \\  local _ENV = {}
        \\  y = 2
        \\  local function f() return z end
        \\end
        \\local function g(_ENV) return w end
        \\_ENV.v = 1
        \\_G.u = 1
    , &.{
        .{ "x", 1, .write },
        .{ "_G", 9, .read },
    });
}

test "analyze handles global declarations" {
    try expectGlobals(
        \\global a, b = 1, 2
        \\global c
        \\global *
        \\d = c
    , &.{
        .{ "a", 1, .write },
        .{ "b", 1, .write },
        .{ "d", 4, .write },
        .{ "c", 4, .read },
    });
}

test "analyze rejects chunks that don't compile" {
    try std.testing.expectError(error.SyntaxError, api.analyze(a, "x = = 1"));
    try std.testing.expectError(error.SyntaxError, api.analyze(a, "global x\ny = 1"));
    try std.testing.expectError(error.SyntaxError, api.analyze(a, "local x <const> = 1\nx = 2"));
}

test "analyze agrees with what a chunk touches when it runs" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    const source =
        \\result = 40 + two
    ;
    var analysis = try api.analyze(a, source);
    defer analysis.deinit();
    try lua.setGlobal("two", @as(i64, 2));
    try lua.doString(source, .{});
    for (analysis.globals) |use| {
        var value = try lua.getGlobal(use.name, api.Value);
        defer value.deinit();
        try std.testing.expect(value != .nil);
    }
    try std.testing.expectEqual(@as(i64, 42), try lua.getGlobal("result", i64));
}
