const std = @import("std");
const process = @import("../process.zig");
const results = @import("results.zig");
const Options = @import("options.zig").Options;
const Phases = struct {
    newstate: results.Metric,
    openlibs: results.Metric,
    @"register-3": results.Metric,
    @"startup-total": results.Metric,
    load: results.Metric,
    call: results.Metric,
    close: results.Metric,
    @"first-chunk": results.Metric,
};
const WorkerReport = struct {
    protocol_version: u32,
    samples: []const struct { phases: Phases },
};

pub fn collect(allocator: std.mem.Allocator, io: std.Io, options: Options, suite: *results.Suite) !void {
    const iterations = options.iterations orelse 1000;
    const warmup = options.warmup orelse 100;
    const engine = "clua";
    const executable = options.clua_c;
    for ([_][]const u8{ "full", "base+host-3" }, 0..) |name, host| {
        if (!options.matches("startup", engine, name)) continue;
        if (options.list) {
            try suite.addCase("startup", engine, name, "Upstream Lua creation, libraries, and first chunk");
            continue;
        }
        collectCase(allocator, io, options, suite, engine, executable, name, host) catch |err| {
            if (err == error.OutOfMemory) return err;
            try suite.add(.{
                .group = "startup",
                .engine = engine,
                .build_mode = options.c_build,
                .executable = executable,
                .case = name,
                .operation = "worker",
                .scope = "In-process phases; worker failed",
                .iterations = iterations,
                .warmup = warmup,
                .status = .failed,
                .reason = @errorName(err),
            });
        };
    }
}

test "worker protocol retains unavailable runtime memory" {
    const parsed = try std.json.parseFromSlice(results.Metric, std.testing.allocator, "{\"elapsed_ns\":7,\"allocations\":1,\"resizes\":0,\"requested_bytes\":8,\"live_bytes\":8,\"peak_bytes\":8}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?u64, null), parsed.value.runtime_bytes);
    try std.testing.expectEqual(@as(?u64, 0), parsed.value.resizes);
}

fn collectCase(allocator: std.mem.Allocator, io: std.Io, options: Options, suite: *results.Suite, engine: []const u8, executable: ?[]const u8, name: []const u8, host: usize) !void {
    const iterations = options.iterations orelse 1000;
    const warmup = options.warmup orelse 100;
    const exe = executable orelse return error.MissingCStartupWorker;
    const iteration_arg = try std.fmt.allocPrint(allocator, "{d}", .{iterations});
    defer allocator.free(iteration_arg);
    const warmup_arg = try std.fmt.allocPrint(allocator, "{d}", .{warmup});
    defer allocator.free(warmup_arg);
    // This timeout covers the entire worker, unlike the process family's per-sample timeout.
    var run = try process.runProcess(allocator, io, &.{ exe, iteration_arg, warmup_arg, if (host == 0) "0" else "1" }, .{
        .timeout_ms = options.timeout_ms orelse 0,
        .max_output_bytes = try std.math.mul(usize, iterations, 2048),
    });
    defer run.deinit(allocator);
    if (!run.success()) {
        try suite.add(.{
            .group = "startup",
            .engine = engine,
            .build_mode = options.c_build,
            .executable = exe,
            .case = name,
            .operation = "worker",
            .scope = "In-process phases; worker failed",
            .iterations = iterations,
            .warmup = warmup,
            .status = if (run.timed_out) .timed_out else .failed,
            .reason = if (run.stderr.len > 0) run.stderr else "C startup worker exited unsuccessfully",
        });
        return;
    }
    const parsed = try std.json.parseFromSlice(WorkerReport, allocator, run.stdout, .{});
    defer parsed.deinit();
    if (parsed.value.protocol_version != 1 or parsed.value.samples.len != iterations) return error.InvalidWorkerReport;
    inline for (std.meta.fields(Phases)) |field| {
        const phase_name = field.name;
        if (!(std.mem.eql(u8, phase_name, "register-3") and host == 0)) {
            const metrics = try allocator.alloc(results.Metric, iterations);
            defer allocator.free(metrics);
            for (parsed.value.samples, metrics) |sample, *metric| metric.* = @field(sample.phases, phase_name);
            try suite.add(.{
                .group = "startup",
                .case = name,
                .engine = engine,
                .build_mode = options.c_build,
                .executable = exe,
                .operation = phase_name,
                .scope = "In-process phase; totals sum initialization/load/call phases",
                .memory_scope = .vm,
                .iterations = iterations,
                .warmup = warmup,
                .samples = metrics,
            });
        }
    }
}
