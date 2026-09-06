const std = @import("std");
const clua = @import("../clua.zig");
const process = @import("../process.zig");
const fixtures = @import("fixtures.zig");
const Options = @import("options.zig").Options;
const results = @import("results.zig");
const stats = @import("stats.zig");
const legacy = @import("legacy_process.zig");
const Timestamp = std.Io.Timestamp;
const max_output_bytes = 1024 * 1024;
const TimedRun = struct { result: process.ProcessResult, elapsed_ns: u64 };

pub fn collect(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map, zlua_exe: []const u8, options: Options, suite: *results.Suite) !void {
    var benchmarks: std.ArrayList(fixtures.Benchmark) = .empty;
    defer {
        for (benchmarks.items) |*benchmark| benchmark.deinit(allocator);
        benchmarks.deinit(allocator);
    }
    try fixtures.discoverBenchmarks(allocator, io, options.bench_root, &benchmarks);
    std.mem.sort(fixtures.Benchmark, benchmarks.items, {}, struct {
        fn less(_: void, a: fixtures.Benchmark, b: fixtures.Benchmark) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.less);
    var selected: std.ArrayList(usize) = .empty;
    defer selected.deinit(allocator);
    // In an all-family run a selector may belong to another family.
    if (options.family == .all) {
        for (benchmarks.items, 0..) |b, index| {
            if (options.category) |category| if (!std.mem.eql(u8, category, b.category) and !std.mem.eql(u8, category, "process")) continue;
            if (options.selectors.len == 0) {
                try selected.append(allocator, index);
                continue;
            }
            for (options.selectors) |selector| {
                if (std.mem.eql(u8, selector, "process") or fixtures.selectorMatches(b, selector)) {
                    try selected.append(allocator, index);
                    break;
                }
            }
        }
    } else if (!try fixtures.resolveSelectors(allocator, io, benchmarks.items, options, &selected)) return error.UnknownSelector;
    if (options.list) {
        for (selected.items) |index| try suite.addCase("process", "zlua+clua", benchmarks.items[index].name, "Complete program, including process launch and compilation");
        return;
    }
    if (selected.items.len == 0) return;
    const discovery = try clua.detect(allocator, io, environ_map, options.clua);
    defer discovery.deinit(allocator);
    const clua_exe = switch (discovery) {
        .found => |path| path,
        .missing => return error.CluaNotFound,
    };
    const zlua_path = options.zlua orelse zlua_exe;
    if (!try validateZlua(allocator, io, zlua_path)) return error.ZluaNotRunnable;
    var reports: std.ArrayList(legacy.BenchmarkReport) = .empty;
    defer {
        for (reports.items) |*report| report.deinit(allocator);
        reports.deinit(allocator);
    }
    var counts: legacy.Counts = .{};
    for (selected.items) |index| {
        const report = runOne(allocator, io, benchmarks.items[index], clua_exe, zlua_path, options) catch |err| report: {
            if (err == error.OutOfMemory) return err;
            const b = benchmarks.items[index];
            break :report legacy.BenchmarkReport{
                .path = b.path,
                .name = b.name,
                .category = b.category,
                .status = .failed,
                .reason = @errorName(err),
                .iterations = options.iterations orelse b.iterations,
                .warmup = options.warmup orelse b.warmup,
                .timeout_ms = options.timeout_ms orelse b.timeout_ms,
            };
        };
        try reports.append(allocator, report);
        switch (report.status) {
            .benchmarked => counts.benchmarked += 1,
            .skipped => counts.skipped += 1,
            .failed => counts.failed += 1,
            .timed_out => counts.timed_out += 1,
        }
        inline for (.{ "clua", "zlua" }) |engine| {
            const data = @field(report, engine);
            const samples = try allocator.alloc(results.Metric, data.samples_ns.len);
            defer allocator.free(samples);
            for (data.samples_ns, samples) |time, *sample| sample.* = .{ .elapsed_ns = time };
            try suite.add(.{
                .group = "process",
                .case = report.name,
                .category = report.category,
                .engine = engine,
                .build_mode = if (std.mem.eql(u8, engine, "clua")) options.clua_build else options.zlua_build,
                .executable = if (std.mem.eql(u8, engine, "clua")) clua_exe else zlua_path,
                .failure_sample = report.failure_sample,
                .failure_during_warmup = report.failure_during_warmup,
                .operation = "program",
                .scope = "Process launch, initialization, loading, compilation, execution, and shutdown",
                .iterations = report.iterations,
                .warmup = report.warmup,
                .timeout_ms = report.timeout_ms,
                .status = @enumFromInt(@intFromEnum(report.status)),
                .reason = report.reason,
                .samples = samples,
            });
        }
    }
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);
    try legacy.appendJsonReport(allocator, &bytes, reports.items, counts);
    suite.legacy_process = try std.json.parseFromSliceLeaky(std.json.Value, suite.arena.allocator(), bytes.items, .{ .allocate = .alloc_always });
}

fn runOne(allocator: std.mem.Allocator, io: std.Io, benchmark: fixtures.Benchmark, clua_exe: []const u8, zlua_exe: []const u8, options: Options) !legacy.BenchmarkReport {
    const iterations = options.iterations orelse benchmark.iterations;
    const warmup = options.warmup orelse benchmark.warmup;
    const timeout_ms = options.timeout_ms orelse benchmark.timeout_ms;
    var report: legacy.BenchmarkReport = .{ .path = benchmark.path, .name = benchmark.name, .category = benchmark.category, .status = .benchmarked, .iterations = iterations, .warmup = warmup, .timeout_ms = timeout_ms };
    if (benchmark.expect == .skip or benchmark.expect == .fail) {
        report.status = .skipped;
        report.reason = benchmark.reason;
        return report;
    }
    report.clua.samples_ns = try allocator.alloc(u64, iterations);
    errdefer allocator.free(report.clua.samples_ns);
    report.zlua.samples_ns = try allocator.alloc(u64, iterations);
    errdefer allocator.free(report.zlua.samples_ns);
    var validation: Validation = .{};
    var failure_index: ?usize = null;
    // Alternate the first engine in each pair, including warmups. Validation is outside runTimed.
    for (0..try std.math.add(usize, iterations, warmup)) |index| {
        var pair: [2]TimedRun = undefined;
        const first: usize = index % 2;
        pair[first] = try runTimed(allocator, io, if (first == 0) clua_exe else zlua_exe, benchmark.path, if (first == 0) .clua else .zlua, timeout_ms, first == 1 and options.debug_errors);
        defer pair[first].result.deinit(allocator);
        const second = 1 - first;
        pair[second] = try runTimed(allocator, io, if (second == 0) clua_exe else zlua_exe, benchmark.path, if (second == 0) .clua else .zlua, timeout_ms, second == 1 and options.debug_errors);
        defer pair[second].result.deinit(allocator);
        const previous = validation.status;
        validation.observe(pair[0].result, pair[1].result);
        if (validation.status != previous) {
            failure_index = index;
            if (options.debug_errors) {
                try stderrPrint(io, "{s}, sample {d}: {s}\nclua: {s}\nzlua: {s}\n", .{ benchmark.name, index + 1, validation.reason, pair[0].result.stderr, pair[1].result.stderr });
            }
        }
        if (index >= warmup) {
            report.clua.samples_ns[index - warmup] = pair[0].elapsed_ns;
            report.zlua.samples_ns[index - warmup] = pair[1].elapsed_ns;
        }
        // Preserve the failing pair's exit information rather than replacing it with a later success.
        if (failure_index == index or failure_index == null) {
            report.clua.exit_code = pair[0].result.exit_code;
            report.clua.signal = pair[0].result.signal;
            report.zlua.exit_code = pair[1].result.exit_code;
            report.zlua.signal = pair[1].result.signal;
        }
        report.clua.timed_out = report.clua.timed_out or pair[0].result.timed_out;
        report.zlua.timed_out = report.zlua.timed_out or pair[1].result.timed_out;
    }
    if (failure_index) |index| {
        report.failure_during_warmup = index < warmup;
        report.failure_sample = if (index < warmup) index else index - warmup;
    }
    report.status = validation.status;
    report.reason = validation.reason;
    report.clua.stats = try stats.calculate(allocator, report.clua.samples_ns);
    report.zlua.stats = try stats.calculate(allocator, report.zlua.samples_ns);
    return report;
}

const Validation = struct {
    status: @import("legacy_process.zig").BenchStatus = .benchmarked,
    reason: []const u8 = "",
    fn observe(self: *Validation, a: process.ProcessResult, b: process.ProcessResult) void {
        if (a.timed_out or b.timed_out) {
            self.status = .timed_out;
            self.reason = "sample timed out";
        }
        if (self.status == .timed_out) return;
        if (!a.success() or !b.success()) {
            self.status = .failed;
            self.reason = "sample exited unsuccessfully";
        } else if (!resultsEqual(a, b)) {
            self.status = .failed;
            self.reason = "incompatible sample output";
        }
    }
};

fn validateZlua(allocator: std.mem.Allocator, io: std.Io, zlua_exe: []const u8) !bool {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, zlua_exe);
    try argv.append(allocator, "--version");
    var result = process.runProcess(allocator, io, argv.items, .{ .timeout_ms = 2000, .expand_arg0 = true }) catch return false;
    defer result.deinit(allocator);
    return result.success();
}

const Engine = enum { clua, zlua };

fn runTimed(
    allocator: std.mem.Allocator,
    io: std.Io,
    exe: []const u8,
    path: []const u8,
    engine: Engine,
    timeout_ms: u64,
    debug_errors: bool,
) !TimedRun {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, exe);
    if (engine == .zlua and debug_errors) try argv.append(allocator, "--debug-errors");
    try argv.append(allocator, path);

    const start = Timestamp.now(io, .awake);
    const result = try process.runProcess(allocator, io, argv.items, .{
        .timeout_ms = timeout_ms,
        .max_output_bytes = max_output_bytes,
        .expand_arg0 = engine == .zlua,
    });
    const elapsed = start.durationTo(Timestamp.now(io, .awake));
    return .{ .result = result, .elapsed_ns = @intCast(elapsed.toNanoseconds()) };
}

fn resultsEqual(clua_result: process.ProcessResult, zlua_result: process.ProcessResult) bool {
    return clua_result.exit_code == zlua_result.exit_code and
        clua_result.signal == zlua_result.signal and
        clua_result.timed_out == zlua_result.timed_out and
        std.mem.eql(u8, clua_result.stdout, zlua_result.stdout) and
        std.mem.eql(u8, clua_result.stderr, zlua_result.stderr);
}

fn stderrPrint(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.print(fmt, args);
    try writer.interface.flush();
}

test "later sample failures and timeouts cannot be hidden by successful samples" {
    const a = std.testing.allocator;
    var good = try process.ownedResult(a, "ok", "", 0);
    defer good.deinit(a);
    var bad = try process.ownedResult(a, "ok", "", 1);
    defer bad.deinit(a);
    var check: Validation = .{};
    check.observe(good, good);
    check.observe(good, bad);
    check.observe(good, good);
    try std.testing.expectEqual(.failed, check.status);
    bad.timed_out = true;
    check.observe(good, bad);
    check.observe(good, good);
    try std.testing.expectEqual(.timed_out, check.status);
}

test "a later output mismatch invalidates the benchmark" {
    const a = std.testing.allocator;
    var first = try process.ownedResult(a, "ok", "", 0);
    defer first.deinit(a);
    var changed = try process.ownedResult(a, "different", "", 0);
    defer changed.deinit(a);
    var check: Validation = .{};
    check.observe(first, first);
    check.observe(first, changed);
    check.observe(first, first);
    try std.testing.expectEqual(.failed, check.status);
    try std.testing.expectEqualStrings("incompatible sample output", check.reason);
}
