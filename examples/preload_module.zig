const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    // Lazy: openHost runs on the first require("host"), with ("host", ":preload:").
    try lua.preloadModuleFn("host", openHost);

    // Eager: an already built table goes straight into package.loaded.
    var config = try lua.newTable(.{});
    defer config.deinit();
    try config.set("greeting", "hello");
    try lua.setLoadedModule("config", config);

    var chunk = try lua.loadString(
        \\local host = require("host")
        \\local config = require("config")
        \\return config.greeting .. " from " .. host.name, host.double(21)
    , .{ .name = "=preload_module" });
    defer chunk.deinit();

    var greeting, const doubled = try chunk.call(.{}, struct { zlua.String, i64 });
    defer greeting.deinit();
    std.debug.print("{f} {d}\n", .{ greeting, doubled });

    // The host can require modules too; this returns the cached table.
    var host = try lua.require("host", zlua.Table);
    defer host.deinit();
    var loaded_by = try host.get("loaded_by", zlua.String);
    defer loaded_by.deinit();
    std.debug.print("loaded by {f}\n", .{loaded_by});
}

fn openHost(ctx: *zlua.Context, name: []const u8, loader_data: []const u8) !zlua.Table {
    _ = name;
    var module = try ctx.state().newTable(.{});
    errdefer module.deinit();

    var double_fn = try ctx.state().newFunction("host_double", hostDouble);
    defer double_fn.deinit();
    try module.set("double", double_fn);
    try module.set("name", "host-module");
    try module.set("loaded_by", loader_data);
    return module;
}

fn hostDouble(ctx: *zlua.Context) !void {
    const value = try ctx.arg(0, i64);
    try ctx.returnValues(value * 2);
}
