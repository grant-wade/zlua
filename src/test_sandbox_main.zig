const std = @import("std");
const zlua = @import("zlua");

pub fn main(init: std.process.Init) !void {
    const arena_allocator = init.arena.allocator();
    const raw_args = try init.minimal.args.toSlice(arena_allocator);
    const args = try arena_allocator.alloc([]const u8, raw_args.len);
    for (raw_args, 0..) |arg, index| args[index] = arg;

    const runner = zlua.testing.sandbox_runner;
    if (args.len == 4 and std.mem.eql(u8, args[1], "--child")) {
        return runner.runChild(std.heap.smp_allocator, init.io, args[2], try std.fmt.parseInt(usize, args[3], 10));
    }
    if (args.len == 5 and std.mem.eql(u8, args[1], "--generate")) {
        return runner.generatePrograms(std.heap.smp_allocator, init.io, args[2], try std.fmt.parseInt(usize, args[3], 10), try std.fmt.parseInt(u64, args[4], 10));
    }
    const exit_code = try runner.runCli(std.heap.smp_allocator, init.io, args[0], args[1..]);
    std.process.exit(exit_code);
}
