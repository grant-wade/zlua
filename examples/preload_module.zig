const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    // Lazy: openHost runs on the first require("host"), with ("host", ":preload:").
    try lua.preloadModuleFn("host", openHost);

    // Eager: an already built table goes straight into package.loaded.
    var config = try lua.createModule("config");
    defer config.deinit();
    try config.set("greeting", "hello");
    try lua.setLoadedModule("config", config);

    var chunk = try lua.loadString(
        \\local host = require("host")
        \\local config = require("config")
        \\return config.greeting .. " from " .. host.name, host.double(21)
    , .{ .name = "=preload_module" });
    defer chunk.deinit();

    const Result = zlua.Tuple(&.{ []const u8, i64 });
    var result = try chunk.call(.{}, Result);
    defer result.deinit();
    std.debug.print("{s} {d}\n", .{ result.get(0), result.get(1) });

    // The host can require modules too; this returns the cached table.
    var host = try lua.require("host", zlua.Table);
    defer host.deinit();
    std.debug.print("loaded by {s}\n", .{try host.get("loaded_by", []const u8)});
}

fn openHost(ctx: *zlua.Context, name: []const u8, loader_data: []const u8) !zlua.Table {
    var module = try ctx.state().createModule(name);
    errdefer module.deinit();

    var double_fn = try ctx.state().register("host_double", hostDouble);
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
