const std = @import("std");
const zlua = @import("zlua");

pub fn main(init: std.process.Init) !void {
    const arena_allocator = init.arena.allocator();

    const raw_args = try init.minimal.args.toSlice(arena_allocator);
    const args = try arena_allocator.alloc([]const u8, raw_args.len);
    for (raw_args, 0..) |arg, index| args[index] = arg;

    // Stack-trace capture on every allocation made the in-process runs about 10x slower.
    var debug_allocator: std.heap.DebugAllocator(.{ .stack_trace_frames = 0 }) = .init;
    const exit_code = try zlua.testing.diff_runner.runCli(debug_allocator.allocator(), init.io, init.environ_map, args[1..]);
    _ = debug_allocator.deinit();
    std.process.exit(exit_code);
}
