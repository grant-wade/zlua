//! Complete-program worker using a snapshot-restored state.
const std = @import("std");
const zlua = @import("zlua");

pub fn main(init: std.process.Init) !void {
    std.process.exit(try run(init));
}

fn run(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 2 and std.mem.eql(u8, args[1], "--version")) return 0;
    const debug = args.len > 1 and std.mem.eql(u8, args[1], "--debug-errors");
    const script_index: usize = if (debug) 2 else 1;
    if (args.len != script_index + 1) return error.ExpectedScript;
    const path = args[script_index];
    const allocator = std.heap.smp_allocator;
    var baseline = try zlua.State.init(allocator, .{
        .stdlib = .full,
        .capabilities = .{
            .io = .{ .runtime = init.io },
            .filesystem = .host_cwd,
            .environment = .{ .map = init.environ_map },
            .process = .enabled,
            .clock = .system,
        },
        .debug = .{ .errors = debug },
    });
    defer baseline.deinit();
    const arg_value = try baseline.raw_state.newTableWithHints(@intCast(args.len), 0);
    for (args, 0..) |arg, index| {
        const key = @as(i64, @intCast(index)) - @as(i64, @intCast(script_index));
        try baseline.raw_state.setTableRaw(arg_value.table, .{ .integer = key }, .{ .string = try baseline.raw_state.intern(arg) });
    }
    try baseline.raw_state.putGlobal("arg", arg_value);

    // Capture libraries and CLI globals before loading the program. The whole
    // worker lifecycle, including capture and restoration, is process-timed.
    var snapshot = try baseline.snapshot(allocator);
    defer snapshot.deinit();
    var worker = try snapshot.newState(allocator);
    defer worker.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(source);
    const source_name = try std.fmt.allocPrint(allocator, "@{s}", .{path});
    defer allocator.free(source_name);
    const chunk = if (source.len > 0 and source[0] == '#')
        if (std.mem.indexOfScalar(u8, source, '\n')) |newline| source[newline + 1 ..] else ""
    else
        source;
    var exit_code: u8 = 0;
    worker.raw_state.executeSourceChunkNamed(chunk, source_name) catch |err| {
        const detail = try worker.raw_state.errorDetailAlloc(allocator, err);
        defer allocator.free(detail);
        try worker.raw_state.stderr.appendSlice(worker.raw_state.allocator, detail);
        try worker.raw_state.stderr.append(worker.raw_state.allocator, '\n');
        exit_code = 1;
    };
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try stdout.interface.writeAll(worker.raw_state.stdout.items);
    try stdout.interface.flush();
    var stderr = std.Io.File.stderr().writer(init.io, &buffer);
    try stderr.interface.writeAll(worker.raw_state.stderr.items);
    try stderr.interface.flush();
    return exit_code;
}
