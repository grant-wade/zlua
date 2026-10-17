const std = @import("std");
const builtin = @import("builtin");

/// Runs `runOne(context, index)` for every index below `count` on up to `jobs`
/// workers (0 means one per CPU), then calls `report(context, index)` serially
/// and in index order as each prefix of the results completes. Returns the
/// first error from either.
pub fn forEachOrdered(
    allocator: std.mem.Allocator,
    io: std.Io,
    jobs: usize,
    count: usize,
    context: anytype,
    comptime runOne: fn (@TypeOf(context), usize) anyerror!void,
    comptime report: fn (@TypeOf(context), usize) anyerror!void,
) !void {
    const Context = @TypeOf(context);
    const State = struct {
        mutex: std.Io.Mutex = .init,
        next_index: std.atomic.Value(usize) = .init(0),
        next_report: usize = 0,
        finished: []bool,
        first_error: ?anyerror = null,

        fn worker(state: *@This(), worker_io: std.Io, total: usize, ctx: Context) void {
            while (true) {
                const index = state.next_index.fetchAdd(1, .monotonic);
                if (index >= total) return;
                const result = runOne(ctx, index);

                state.mutex.lockUncancelable(worker_io);
                defer state.mutex.unlock(worker_io);
                result catch |err| state.recordError(err);
                state.finished[index] = true;
                while (state.next_report < total and state.finished[state.next_report]) : (state.next_report += 1) {
                    report(ctx, state.next_report) catch |err| state.recordError(err);
                }
            }
        }

        fn recordError(state: *@This(), err: anyerror) void {
            if (state.first_error == null) state.first_error = err;
        }
    };

    const finished = try allocator.alloc(bool, count);
    defer allocator.free(finished);
    @memset(finished, false);

    const workers = if (jobs == 0) std.Thread.getCpuCount() catch 1 else jobs;
    // Zig 0.16 can leak inheritable pipe writers between concurrent Windows spawns.
    const safe_workers = if (builtin.os.tag == .windows and builtin.zig_version.order(.{ .major = 0, .minor = 17, .patch = 0 }) == .lt) 1 else workers;
    var state: State = .{ .finished = finished };
    var group: std.Io.Group = .init;
    for (0..@max(1, @min(safe_workers, count))) |_| group.async(io, State.worker, .{ &state, io, count, context });
    try group.await(io);

    if (state.first_error) |err| return err;
}

test "ordered fan-out reports every index in order" {
    const Context = struct {
        ran: [64]std.atomic.Value(bool) = @splat(.init(false)),
        reported: std.ArrayList(usize) = .empty,

        fn runOne(self: *@This(), index: usize) anyerror!void {
            self.ran[index].store(true, .monotonic);
        }

        fn report(self: *@This(), index: usize) anyerror!void {
            try std.testing.expect(self.ran[index].load(.monotonic));
            try self.reported.append(std.testing.allocator, index);
        }
    };

    var context: Context = .{};
    defer context.reported.deinit(std.testing.allocator);
    try forEachOrdered(std.testing.allocator, std.testing.io, 4, context.ran.len, &context, Context.runOne, Context.report);

    try std.testing.expectEqual(context.ran.len, context.reported.items.len);
    for (context.reported.items, 0..) |index, expected| try std.testing.expectEqual(expected, index);
}

test "ordered fan-out returns the first error after finishing" {
    const Context = struct {
        reported: usize = 0,

        fn runOne(_: *@This(), index: usize) anyerror!void {
            if (index == 3) return error.Boom;
        }

        fn report(self: *@This(), _: usize) anyerror!void {
            self.reported += 1;
        }
    };

    var context: Context = .{};
    try std.testing.expectError(error.Boom, forEachOrdered(std.testing.allocator, std.testing.io, 2, 8, &context, Context.runOne, Context.report));
    try std.testing.expectEqual(@as(usize, 8), context.reported);
}
