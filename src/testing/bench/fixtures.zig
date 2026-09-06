const std = @import("std");
const Options = @import("options.zig").Options;
const Dir = std.Io.Dir;
const File = std.Io.File;
const default_bench_root = "tests/bench";
const parsePositiveUsize = @import("options.zig").parsePositiveUsize;
const parsePositiveU64 = @import("options.zig").parsePositiveU64;
const max_output_bytes = 1024 * 1024;
const default_iterations = 30;
const default_warmup = 1;
const default_timeout_ms = 60_000;
const Expect = enum { pass, fail, skip };
pub const Benchmark = struct {
    path: []u8,
    name: []u8,
    category: []u8,
    iterations: usize,
    warmup: usize,
    timeout_ms: u64,
    expect: Expect,
    reason: []u8,

    pub fn deinit(self: *Benchmark, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.name);
        allocator.free(self.category);
        allocator.free(self.reason);
        self.* = undefined;
    }
};

const ParsedMetadata = struct {
    name: ?[]const u8 = null,
    category: []const u8 = "misc",
    iterations: usize = default_iterations,
    warmup: usize = default_warmup,
    timeout_ms: u64 = default_timeout_ms,
    expect: Expect = .pass,
    reason: []const u8 = "",
};

pub fn discoverBenchmarks(allocator: std.mem.Allocator, io: std.Io, root: []const u8, benchmarks: *std.ArrayList(Benchmark)) !void {
    var dir = try Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".lua")) continue;
        const path = try std.fs.path.join(allocator, &.{ root, entry.path });
        errdefer allocator.free(path);
        try appendBenchmark(allocator, io, benchmarks, path);
    }
}

fn appendBenchmark(allocator: std.mem.Allocator, io: std.Io, benchmarks: *std.ArrayList(Benchmark), owned_path: []u8) !void {
    const source = try Dir.cwd().readFileAlloc(io, owned_path, allocator, .limited(max_output_bytes));
    defer allocator.free(source);

    const parsed = try parseMetadata(source);
    if ((parsed.expect == .skip or parsed.expect == .fail) and parsed.reason.len == 0) return error.MissingBenchmarkReason;
    if (parsed.category.len == 0) return error.InvalidMetadataValue;

    const name_source = parsed.name orelse owned_path;
    const name = try allocator.dupe(u8, name_source);
    errdefer allocator.free(name);
    const category = try allocator.dupe(u8, parsed.category);
    errdefer allocator.free(category);
    const reason = try allocator.dupe(u8, parsed.reason);
    errdefer allocator.free(reason);
    const benchmark: Benchmark = .{
        .path = owned_path,
        .name = name,
        .category = category,
        .iterations = parsed.iterations,
        .warmup = parsed.warmup,
        .timeout_ms = parsed.timeout_ms,
        .expect = parsed.expect,
        .reason = reason,
    };
    try benchmarks.append(allocator, benchmark);
}

fn parseMetadata(source: []const u8) !ParsedMetadata {
    var result: ParsedMetadata = .{};
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "--")) break;

        const comment = std.mem.trim(u8, line[2..], " \t");
        const colon = std.mem.indexOfScalar(u8, comment, ':') orelse continue;
        const key = std.mem.trim(u8, comment[0..colon], " \t");
        const value = std.mem.trim(u8, comment[colon + 1 ..], " \t");

        if (std.mem.eql(u8, key, "name")) {
            if (value.len == 0) return error.InvalidMetadataValue;
            result.name = value;
        } else if (std.mem.eql(u8, key, "category")) {
            if (value.len == 0) return error.InvalidMetadataValue;
            result.category = value;
        } else if (std.mem.eql(u8, key, "iterations")) {
            result.iterations = try parsePositiveUsize(value);
        } else if (std.mem.eql(u8, key, "warmup")) {
            result.warmup = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "timeout-ms")) {
            result.timeout_ms = try parsePositiveU64(value);
        } else if (std.mem.eql(u8, key, "expect")) {
            result.expect = try parseExpect(value);
        } else if (std.mem.eql(u8, key, "reason")) {
            result.reason = value;
        }
    }
    return result;
}

fn parseExpect(value: []const u8) !Expect {
    return std.meta.stringToEnum(Expect, value) orelse error.InvalidMetadataValue;
}

pub fn resolveSelectors(
    allocator: std.mem.Allocator,
    io: std.Io,
    benchmarks: []const Benchmark,
    options: Options,
    selected: *std.ArrayList(usize),
) !bool {
    if (options.selectors.len == 0) {
        for (benchmarks, 0..) |benchmark, index| {
            if (matchesCategory(benchmark, options.category)) try selected.append(allocator, index);
        }
        return true;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = File.stderr().writer(io, &stderr_buffer);
    const err_out = &stderr_writer.interface;
    var ok = true;

    for (options.selectors) |selector| {
        const directory_selector = selectorMatchesDirectory(benchmarks, selector);
        var matches = std.ArrayList(usize).empty;
        defer matches.deinit(allocator);

        for (benchmarks, 0..) |benchmark, index| {
            if (!matchesCategory(benchmark, options.category)) continue;
            if (selectorMatches(benchmark, selector)) try matches.append(allocator, index);
        }

        if (matches.items.len == 0) {
            try err_out.print("bench: no benchmark matches '{s}'\n", .{selector});
            try printSelectorSuggestions(err_out, benchmarks, options.category, selector);
            ok = false;
        } else if (matches.items.len > 1 and !directory_selector) {
            try err_out.print("bench: selector '{s}' is ambiguous; choose one of:\n", .{selector});
            for (matches.items) |index| try err_out.print("  {s}\n", .{benchmarks[index].path});
            ok = false;
        } else {
            for (matches.items) |index| {
                if (!containsIndex(selected.items, index)) try selected.append(allocator, index);
            }
        }
    }
    try err_out.flush();
    return ok;
}

fn printSelectorSuggestions(out: anytype, benchmarks: []const Benchmark, category: ?[]const u8, selector: []const u8) !void {
    var printed_header = false;
    for (benchmarks) |benchmark| {
        if (!matchesCategory(benchmark, category)) continue;
        const relative = relativeBenchPath(benchmark.path);
        const basename = std.fs.path.basename(benchmark.path);
        const basename_without_ext = if (std.mem.endsWith(u8, basename, ".lua")) basename[0 .. basename.len - 4] else basename;
        const relative_without_ext = if (std.mem.endsWith(u8, relative, ".lua")) relative[0 .. relative.len - 4] else relative;

        const candidates = [_][]const u8{ benchmark.name, relative_without_ext, basename_without_ext };
        for (candidates) |candidate| {
            if (candidate.len == 0) continue;
            if (editDistanceAtMost(selector, candidate, 3)) {
                if (!printed_header) {
                    try out.print("bench: did you mean:\n", .{});
                    printed_header = true;
                }
                try out.print("  {s}\n", .{candidate});
            }
        }
    }
    if (!printed_header) try out.print("bench: use --list to show available benchmarks\n", .{});
}

fn editDistanceAtMost(lhs: []const u8, rhs: []const u8, max_distance: usize) bool {
    if (lhs.len > rhs.len + max_distance or rhs.len > lhs.len + max_distance) return false;

    var distance: usize = 0;
    var lhs_index: usize = 0;
    var rhs_index: usize = 0;
    while (lhs_index < lhs.len and rhs_index < rhs.len) {
        if (lhs[lhs_index] == rhs[rhs_index]) {
            lhs_index += 1;
            rhs_index += 1;
            continue;
        }

        distance += 1;
        if (distance > max_distance) return false;

        if (lhs.len > rhs.len) {
            lhs_index += 1;
        } else if (rhs.len > lhs.len) {
            rhs_index += 1;
        } else {
            lhs_index += 1;
            rhs_index += 1;
        }
    }

    distance += lhs.len - lhs_index;
    distance += rhs.len - rhs_index;
    return distance <= max_distance;
}

pub fn selectorMatches(benchmark: Benchmark, raw_selector: []const u8) bool {
    const selector = processSelector(raw_selector);
    if (std.mem.eql(u8, selector, "process") or selector.len == 0) return true;
    return std.mem.eql(u8, selector, benchmark.name) or
        pathSelectorMatches(benchmark.path, selector) or
        pathSelectorMatches(relativeBenchPath(benchmark.path), selector) or
        basenameSelectorMatches(benchmark.path, selector) or
        selectorMatchesPathDirectory(benchmark.path, selector) or
        selectorMatchesPathDirectory(relativeBenchPath(benchmark.path), selector);
}

fn selectorMatchesDirectory(benchmarks: []const Benchmark, raw_selector: []const u8) bool {
    const selector = processSelector(raw_selector);
    if (std.mem.eql(u8, selector, "process") or selector.len == 0) return true;
    for (benchmarks) |benchmark| {
        if (selectorMatchesPathDirectory(benchmark.path, selector) or selectorMatchesPathDirectory(relativeBenchPath(benchmark.path), selector)) {
            return true;
        }
    }
    return false;
}

fn pathSelectorMatches(path: []const u8, selector: []const u8) bool {
    if (std.mem.eql(u8, path, selector)) return true;
    if (std.mem.endsWith(u8, selector, ".lua")) return false;
    return std.mem.eql(u8, path, selectorWithLua(path, selector));
}

fn selectorWithLua(path: []const u8, selector: []const u8) []const u8 {
    if (!std.mem.endsWith(u8, path, ".lua")) return selector;
    const without_ext = path[0 .. path.len - 4];
    if (std.mem.eql(u8, without_ext, selector)) return path;
    return selector;
}

fn basenameSelectorMatches(path: []const u8, selector: []const u8) bool {
    const basename = std.fs.path.basename(path);
    if (std.mem.eql(u8, basename, selector)) return true;
    if (std.mem.endsWith(u8, selector, ".lua")) return false;
    return basename.len > 4 and std.mem.eql(u8, basename[0 .. basename.len - 4], selector);
}

fn selectorMatchesPathDirectory(path: []const u8, selector: []const u8) bool {
    var trimmed = selector;
    while (trimmed.len > 0 and trimmed[trimmed.len - 1] == '/') trimmed = trimmed[0 .. trimmed.len - 1];
    if (trimmed.len == 0) return false;
    if (!std.mem.startsWith(u8, path, trimmed)) return false;
    return path.len > trimmed.len and path[trimmed.len] == '/';
}

pub fn relativeBenchPath(path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, default_bench_root ++ "/")) return path[default_bench_root.len + 1 ..];
    return path;
}

fn matchesCategory(benchmark: Benchmark, category: ?[]const u8) bool {
    return category == null or std.mem.eql(u8, benchmark.category, category.?);
}

fn containsIndex(items: []const usize, needle: usize) bool {
    for (items) |item| if (item == needle) return true;
    return false;
}

test "metadata parser accepts benchmark fields" {
    const parsed = try parseMetadata(
        \\-- name: vm/arithmetic
        \\-- category: vm
        \\-- iterations: 2
        \\-- warmup: 0
        \\-- timeout-ms: 100
        \\-- expect: pass
        \\
        \\print(1)
    );
    try std.testing.expectEqualStrings("vm/arithmetic", parsed.name.?);
    try std.testing.expectEqualStrings("vm", parsed.category);
    try std.testing.expectEqual(@as(usize, 2), parsed.iterations);
    try std.testing.expectEqual(@as(usize, 0), parsed.warmup);
    try std.testing.expectEqual(@as(u64, 100), parsed.timeout_ms);
    try std.testing.expectEqual(Expect.pass, parsed.expect);
}

fn processSelector(selector: []const u8) []const u8 {
    const prefix = "process/zlua+clua/";
    if (std.mem.startsWith(u8, selector, prefix)) return selector[prefix.len..];
    if (std.mem.eql(u8, selector, "process/zlua+clua")) return "";
    if (std.mem.startsWith(u8, selector, "process/")) return selector[8..];
    return selector;
}

test "listed process paths and legacy selectors select the same fixture" {
    const a = std.testing.allocator;
    var benchmark: Benchmark = .{ .path = try a.dupe(u8, "tests/bench/table/reads.lua"), .name = try a.dupe(u8, "table/reads"), .category = try a.dupe(u8, "table"), .iterations = 5, .warmup = 1, .timeout_ms = 1000, .expect = .pass, .reason = try a.dupe(u8, "") };
    defer benchmark.deinit(a);
    for ([_][]const u8{ "table/reads", "table", "reads", "process/zlua+clua/table/reads", "process", "process/table" }) |selector|
        try std.testing.expect(selectorMatches(benchmark, selector));
    try std.testing.expect(!selectorMatches(benchmark, "startup/native/full"));
}
