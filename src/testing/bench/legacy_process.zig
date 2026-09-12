const std = @import("std");
const TimingStats = @import("stats.zig").TimingStats;
pub const Counts = struct {
    benchmarked: usize = 0,
    skipped: usize = 0,
    failed: usize = 0,
    timed_out: usize = 0,
};

pub const BenchStatus = enum { benchmarked, skipped, failed, timed_out };

const EngineReport = struct {
    samples_ns: []u64 = &.{},
    stats: TimingStats = .{},
    exit_code: ?u8 = null,
    signal: ?u32 = null,
    timed_out: bool = false,

    pub fn jsonStringify(self: EngineReport, json: *std.json.Stringify) !void {
        try json.write(.{
            .samples_ns = self.samples_ns,
            .min_ns = self.stats.min_ns,
            .median_ns = self.stats.median_ns,
            .mean_ns = self.stats.mean_ns,
            .p95_ns = self.stats.p95_ns,
            .max_ns = self.stats.max_ns,
            .stddev_ns = self.stats.stddev_ns,
            .exit_code = self.exit_code,
            .signal = self.signal,
            .timed_out = self.timed_out,
        });
    }
};

pub const BenchmarkReport = struct {
    path: []const u8,
    name: []const u8,
    category: []const u8,
    status: BenchStatus,
    reason: []const u8 = "",
    failure_sample: ?usize = null,
    failure_during_warmup: bool = false,
    iterations: usize = 0,
    warmup: usize = 0,
    timeout_ms: u64 = 0,
    clua: EngineReport = .{},
    zlua: EngineReport = .{},
    zlua_snapshot: EngineReport = .{},

    pub fn jsonStringify(self: BenchmarkReport, json: *std.json.Stringify) !void {
        try json.write(.{
            .path = self.path,
            .name = self.name,
            .category = self.category,
            .status = self.status,
            .iterations = self.iterations,
            .warmup = self.warmup,
            .timeout_ms = self.timeout_ms,
            .ratio_zlua_clua_millionths = if (self.status == .benchmarked)
                @as(?u64, ratioMillionths(self.zlua.stats.mean_ns, self.clua.stats.mean_ns))
            else
                null,
            .median_ratio_zlua_clua = if (self.status == .benchmarked) @import("stats.zig").ratio(self.zlua.stats.median_ns, self.clua.stats.median_ns) else null,
            .median_ratio_snapshot_clua = if (self.status == .benchmarked) @import("stats.zig").ratio(self.zlua_snapshot.stats.median_ns, self.clua.stats.median_ns) else null,
            .median_ratio_snapshot_zlua = if (self.status == .benchmarked) @import("stats.zig").ratio(self.zlua_snapshot.stats.median_ns, self.zlua.stats.median_ns) else null,
            .reason = self.reason,
            .failure_sample = self.failure_sample,
            .failure_during_warmup = self.failure_during_warmup,
            .clua = self.clua,
            .zlua = self.zlua,
            .zlua_snapshot = self.zlua_snapshot,
        });
    }

    pub fn deinit(self: *BenchmarkReport, allocator: std.mem.Allocator) void {
        allocator.free(self.clua.samples_ns);
        allocator.free(self.zlua.samples_ns);
        allocator.free(self.zlua_snapshot.samples_ns);
        self.* = undefined;
    }
};

pub fn appendJsonReport(allocator: std.mem.Allocator, out: *std.ArrayList(u8), reports: []const BenchmarkReport, counts: Counts) !void {
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();
    try std.json.Stringify.value(.{
        .format_version = 1,
        .counts = counts,
        .benchmarks = reports,
    }, .{ .whitespace = .indent_2 }, &writer.writer);
    try out.appendSlice(allocator, writer.written());
    try out.append(allocator, '\n');
}

fn ratioMillionths(numerator: u64, denominator: u64) u64 {
    if (denominator == 0) return std.math.maxInt(u64);
    const millionths: u128 = (@as(u128, numerator) * 1_000_000) / denominator;
    return if (millionths > std.math.maxInt(u64)) std.math.maxInt(u64) else @intCast(millionths);
}

test "json report includes raw samples and metrics" {
    var clua_samples = [_]u64{ 100, 200 };
    var zlua_samples = [_]u64{ 300, 500 };
    const reports = [_]BenchmarkReport{.{
        .path = "tests/bench/vm/arithmetic.lua",
        .name = "vm/arithmetic",
        .category = "vm",
        .status = .benchmarked,
        .iterations = 2,
        .warmup = 1,
        .timeout_ms = 1000,
        .clua = .{
            .samples_ns = clua_samples[0..],
            .stats = .{ .min_ns = 100, .median_ns = 150, .mean_ns = 150, .max_ns = 200, .stddev_ns = 50 },
            .exit_code = 0,
        },
        .zlua = .{
            .samples_ns = zlua_samples[0..],
            .stats = .{ .min_ns = 300, .median_ns = 400, .mean_ns = 400, .max_ns = 500, .stddev_ns = 100 },
            .exit_code = 0,
        },
    }};

    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try appendJsonReport(std.testing.allocator, &out, &reports, .{ .benchmarked = 1 });

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out.items, .{});
    defer parsed.deinit();
    const report = parsed.value.object.get("benchmarks").?.array.items[0].object;
    const clua_engine = report.get("clua").?.object;
    const zlua_engine = report.get("zlua").?.object;
    const samples = clua_engine.get("samples_ns").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), samples.len);
    try std.testing.expectEqual(@as(i64, 100), samples[0].integer);
    try std.testing.expectEqual(@as(i64, 200), samples[1].integer);
    try std.testing.expectEqual(@as(i64, 150), clua_engine.get("median_ns").?.integer);
    try std.testing.expectEqual(@as(i64, 100), zlua_engine.get("stddev_ns").?.integer);
    try std.testing.expectEqual(@as(i64, 2666666), report.get("ratio_zlua_clua_millionths").?.integer);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("format_version").?.integer);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("counts").?.object.get("benchmarked").?.integer);
}

test "json report preserves escaped strings and null results" {
    const reports = [_]BenchmarkReport{.{
        .path = "a\\b\"c\n\x01.lua",
        .name = "example",
        .category = "vm",
        .status = .skipped,
        .reason = "not ready\t yet",
        .zlua = .{ .signal = 9, .timed_out = true },
    }};
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try appendJsonReport(std.testing.allocator, &out, &reports, .{ .skipped = 1 });
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out.items, .{});
    defer parsed.deinit();
    const report = parsed.value.object.get("benchmarks").?.array.items[0].object;
    try std.testing.expectEqualStrings(reports[0].path, report.get("path").?.string);
    try std.testing.expectEqualStrings(reports[0].reason, report.get("reason").?.string);
    try std.testing.expectEqualStrings("skipped", report.get("status").?.string);
    try std.testing.expect(report.get("ratio_zlua_clua_millionths").? == .null);
    const engine = report.get("zlua").?.object;
    try std.testing.expect(engine.get("exit_code").? == .null);
    try std.testing.expectEqual(@as(i64, 9), engine.get("signal").?.integer);
    try std.testing.expect(engine.get("timed_out").?.bool);
    try std.testing.expectEqual(@as(usize, 0), engine.get("samples_ns").?.array.items.len);
}
