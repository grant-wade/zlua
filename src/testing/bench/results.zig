const std = @import("std");
const stats = @import("stats.zig");

pub const Metric = struct {
    elapsed_ns: u64 = 0,
    allocations: ?u64 = null,
    resizes: ?u64 = null,
    requested_bytes: ?u64 = null,
    live_bytes: ?u64 = null,
    peak_bytes: ?u64 = null,
    runtime_bytes: ?u64 = null,
};
pub const MemoryScope = enum { unavailable, vm, checkpoint, new_state };
pub const Status = enum { benchmarked, skipped, failed, timed_out };

pub const BenchmarkResult = struct {
    group: []const u8,
    case: []const u8,
    engine: []const u8,
    operation: []const u8,
    category: []const u8 = "",
    build_mode: ?[]const u8 = null,
    executable: ?[]const u8 = null,
    failure_sample: ?usize = null,
    failure_during_warmup: bool = false,
    scope: []const u8,
    memory_scope: MemoryScope = .unavailable,
    iterations: usize,
    warmup: usize,
    timeout_ms: ?u64 = null,
    status: Status = .benchmarked,
    reason: []const u8 = "",
    samples: []const Metric = &.{},
    timing: ?stats.TimingStats = null,
};

pub const Case = struct { group: []const u8, engine: []const u8, name: []const u8, description: []const u8 };

// Owns copies so collectors can release temporary samples and discovered fixtures.
pub const Suite = struct {
    arena: std.heap.ArenaAllocator,
    results: std.ArrayList(BenchmarkResult) = .empty,
    cases: std.ArrayList(Case) = .empty,
    // The v1 process records remain available under "benchmarks" in JSON v2.
    legacy_process: std.json.Value = .null,

    pub fn init(allocator: std.mem.Allocator) Suite {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }
    pub fn deinit(self: *Suite) void {
        self.arena.deinit();
    }
    pub fn add(self: *Suite, result: BenchmarkResult) !void {
        const allocator = self.arena.allocator();
        var owned = result;
        inline for (.{ "group", "case", "engine", "operation", "category", "scope", "reason" }) |field| {
            @field(owned, field) = try allocator.dupe(u8, @field(result, field));
        }
        if (result.build_mode) |mode| owned.build_mode = try allocator.dupe(u8, mode);
        if (result.executable) |exe| owned.executable = try allocator.dupe(u8, exe);
        owned.samples = try allocator.dupe(Metric, result.samples);
        if (result.status == .benchmarked) {
            const times = try allocator.alloc(u64, result.samples.len);
            defer allocator.free(times);
            for (result.samples, times) |sample, *time| time.* = sample.elapsed_ns;
            owned.timing = try stats.calculate(allocator, times);
        } else owned.timing = null;
        try self.results.append(allocator, owned);
    }
    pub fn addCase(self: *Suite, group: []const u8, engine: []const u8, name: []const u8, description: []const u8) !void {
        const a = self.arena.allocator();
        try self.cases.append(a, .{
            .group = try a.dupe(u8, group),
            .engine = try a.dupe(u8, engine),
            .name = try a.dupe(u8, name),
            .description = try a.dupe(u8, description),
        });
    }
    pub fn failed(self: *const Suite) bool {
        for (self.results.items) |r| if (r.status == .failed or r.status == .timed_out) return true;
        return false;
    }
};
