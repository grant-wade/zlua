const std = @import("std");
const options_module = @import("bench/options.zig");
const results = @import("bench/results.zig");
const report = @import("bench/report.zig");
const process = @import("bench/process.zig");
const startup = @import("bench/startup.zig");
const c_startup = @import("bench/c_startup.zig");
const snapshots = @import("bench/snapshots.zig");

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map, zlua_exe: []const u8, args: []const []const u8) !u8 {
    return run(allocator, io, environ_map, zlua_exe, args) catch |err| {
        var buffer: [1024]u8 = undefined;
        var writer = std.Io.File.stderr().writer(io, &buffer);
        try writer.interface.print("bench: {s}\n", .{@errorName(err)});
        try writer.interface.flush();
        return 2;
    };
}

fn run(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map, zlua_exe: []const u8, args: []const []const u8) !u8 {
    const options = try options_module.parseArgs(allocator, args);
    defer options.deinit(allocator);
    var suite = results.Suite.init(allocator);
    defer suite.deinit();
    // Check every selector before measurement, so a typo cannot silently shorten a mixed run.
    for (options.selectors) |selector| {
        var probe = results.Suite.init(allocator);
        defer probe.deinit();
        var selection = options;
        selection.list = true;
        selection.selectors = &.{selector};
        try collectFamilies(allocator, io, environ_map, zlua_exe, selection, &probe);
        if (probe.cases.items.len == 0) {
            var error_buffer: [1024]u8 = undefined;
            var error_writer = std.Io.File.stderr().writer(io, &error_buffer);
            try error_writer.interface.print("bench: no benchmark matches '{s}'\n", .{selector});
            try error_writer.interface.flush();
            return error.UnknownSelector;
        }
    }
    try collectFamilies(allocator, io, environ_map, zlua_exe, options, &suite);
    if (suite.results.items.len == 0 and suite.cases.items.len == 0) return error.NoMatchingBenchmarks;
    var buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try report.human(allocator, &writer.interface, &suite, options.verbose, options.list);
    try writer.interface.flush();
    if (!options.list) try report.writeFiles(allocator, io, &suite, options.json_path, options.csv_path);
    return if (suite.failed()) 1 else 0;
}

test {
    _ = options_module;
    _ = results;
    _ = report;
    _ = process;
    _ = @import("bench/stats.zig");
    _ = @import("bench/allocation.zig");
    _ = @import("bench/fixtures.zig");
    _ = @import("bench/legacy_process.zig");
    _ = c_startup;
}

fn collectFamilies(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map, zlua_exe: []const u8, options: options_module.Options, suite: *results.Suite) !void {
    // Families run serially. Worker launch and reporting are outside in-process timers.
    if (options.family == .process or options.family == .all)
        try process.collect(allocator, io, environ_map, zlua_exe, options, suite);
    if (options.family == .startup or options.family == .all) {
        try startup.collect(allocator, io, options, suite);
        try c_startup.collect(allocator, io, options, suite);
    }
    if (options.family == .snapshots or options.family == .all)
        try snapshots.collect(allocator, io, options, suite);
}
