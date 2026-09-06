const std = @import("std");

pub const TimingStats = struct {
    min_ns: u64 = 0,
    median_ns: u64 = 0,
    p95_ns: u64 = 0,
    mean_ns: u64 = 0,
    max_ns: u64 = 0,
    stddev_ns: u64 = 0,
};

pub fn medianSortedNs(sorted: []const u64) u64 {
    std.debug.assert(sorted.len > 0);
    const middle = sorted.len / 2;
    return if (sorted.len % 2 == 1) sorted[middle] else @intCast((@as(u128, sorted[middle - 1]) + sorted[middle]) / 2);
}

pub fn calculate(allocator: std.mem.Allocator, samples: []const u64) !TimingStats {
    if (samples.len == 0) return error.NoSamples;
    const sorted = try allocator.dupe(u64, samples);
    defer allocator.free(sorted);
    std.mem.sort(u64, sorted, {}, std.sort.asc(u64));
    var sum: u128 = 0;
    for (samples) |sample| sum += sample;
    const mean: u64 = @intCast(sum / samples.len);
    var variance: f64 = 0;
    for (samples) |sample| {
        const delta = @as(f64, @floatFromInt(sample)) - @as(f64, @floatFromInt(mean));
        variance += delta * delta;
    }
    // Nearest rank for p95; the median averages the two middle observations.
    const rank: usize = @intCast((@as(u128, 95) * samples.len + 99) / 100 - 1);
    return .{ .min_ns = sorted[0], .median_ns = medianSortedNs(sorted), .p95_ns = sorted[rank], .mean_ns = mean, .max_ns = sorted[sorted.len - 1], .stddev_ns = @intFromFloat(@sqrt(variance / @as(f64, @floatFromInt(samples.len)))) };
}

pub fn ratio(numerator: u64, denominator: u64) ?f64 {
    if (denominator == 0) return null;
    return @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
}

pub fn breakEven(capture: u64, reset: u64, rebuild: u64) ?u64 {
    if (rebuild <= reset) return null;
    return std.math.divCeil(u64, capture, rebuild - reset) catch unreachable;
}

test "statistics handle even median, nearest rank p95, and empty samples" {
    const s = try calculate(std.testing.allocator, &.{ 400, 100, 300, 200 });
    try std.testing.expectEqual(@as(u64, 250), s.median_ns);
    try std.testing.expectEqual(@as(u64, 400), s.p95_ns);
    try std.testing.expectEqual(@as(u64, 250), s.mean_ns);
    try std.testing.expectError(error.NoSamples, calculate(std.testing.allocator, &.{}));
    const one = try calculate(std.testing.allocator, &.{7});
    try std.testing.expectEqual(@as(u64, 0), one.stddev_ns);
    const large = try calculate(std.testing.allocator, &.{ std.math.maxInt(u64), std.math.maxInt(u64) });
    try std.testing.expectEqual(std.math.maxInt(u64), large.median_ns);
}

test "comparisons handle no improvement and zero duration" {
    try std.testing.expectEqual(@as(?u64, 4), breakEven(10, 4, 7));
    try std.testing.expectEqual(@as(?u64, null), breakEven(10, 7, 7));
    try std.testing.expectEqual(@as(?u64, null), breakEven(10, 8, 7));
    try std.testing.expectEqual(@as(?f64, null), ratio(1, 0));
}
