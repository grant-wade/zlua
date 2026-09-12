const std = @import("std");
const builtin = @import("builtin");
const results = @import("results.zig");
const stats = @import("stats.zig");
const Result = results.BenchmarkResult;
const Suite = results.Suite;

const Comparison = struct {
    group: []const u8,
    case: []const u8,
    statistic: []const u8 = "median",
    numerator: []const u8,
    denominator: []const u8,
    ratio: ?f64,
    break_even_resets: ?u64 = null,
};

fn find(suite: *const Suite, group: []const u8, case: []const u8, engine: []const u8, operation: []const u8) ?Result {
    for (suite.results.items) |r| {
        if (std.mem.eql(u8, r.group, group) and std.mem.eql(u8, r.case, case) and
            std.mem.eql(u8, r.engine, engine) and std.mem.eql(u8, r.operation, operation)) return r;
    }
    return null;
}

fn median(result: ?Result) ?u64 {
    const r = result orelse return null;
    return if (r.timing) |t| t.median_ns else null;
}

fn comparisons(allocator: std.mem.Allocator, suite: *const Suite) ![]Comparison {
    var list: std.ArrayList(Comparison) = .empty;
    errdefer list.deinit(allocator);
    for (suite.results.items) |r| {
        if (std.mem.eql(u8, r.group, "process") and (std.mem.eql(u8, r.engine, "zlua") or std.mem.eql(u8, r.engine, "zlua_snapshot"))) {
            const a = median(r);
            const b = median(find(suite, r.group, r.case, "clua", "program"));
            try list.append(allocator, .{ .group = r.group, .case = r.case, .numerator = r.engine, .denominator = "clua", .ratio = if (a != null and b != null) stats.ratio(a.?, b.?) else null });
            if (std.mem.eql(u8, r.engine, "zlua_snapshot")) {
                const plain = median(find(suite, r.group, r.case, "zlua", "program"));
                try list.append(allocator, .{ .group = r.group, .case = r.case, .numerator = r.engine, .denominator = "zlua", .ratio = if (a != null and plain != null) stats.ratio(a.?, plain.?) else null });
            }
        } else if (std.mem.eql(u8, r.group, "snapshots") and std.mem.eql(u8, r.operation, "reset")) {
            const reset = median(r);
            const rebuild = median(find(suite, r.group, r.case, r.engine, "rebuild"));
            const capture = median(find(suite, r.group, r.case, r.engine, "capture"));
            try list.append(allocator, .{ .group = r.group, .case = r.case, .numerator = "rebuild", .denominator = "reset", .ratio = if (reset != null and rebuild != null) stats.ratio(rebuild.?, reset.?) else null, .break_even_resets = if (capture != null and reset != null and rebuild != null) stats.breakEven(capture.?, reset.?, rebuild.?) else null });
        }
    }
    return list.toOwnedSlice(allocator);
}

fn timeText(a: std.mem.Allocator, ns: ?u64) ![]const u8 {
    const value = ns orelse return "-";
    if (value < 1000) return std.fmt.allocPrint(a, "{d} ns", .{value});
    if (value < 1_000_000) return std.fmt.allocPrint(a, "{d:.2} us", .{@as(f64, @floatFromInt(value)) / 1000});
    if (value < 1_000_000_000) return std.fmt.allocPrint(a, "{d:.2} ms", .{@as(f64, @floatFromInt(value)) / 1_000_000});
    return std.fmt.allocPrint(a, "{d:.2} s", .{@as(f64, @floatFromInt(value)) / 1_000_000_000});
}
fn ratioText(a: std.mem.Allocator, value: ?f64) ![]const u8 {
    return if (value) |v| std.fmt.allocPrint(a, "{d:.2}x", .{v}) else "-";
}
fn numberText(a: std.mem.Allocator, value: ?u64) ![]const u8 {
    return if (value) |v| std.fmt.allocPrint(a, "{d}", .{v}) else "-";
}

pub fn human(allocator: std.mem.Allocator, out: *std.Io.Writer, suite: *const Suite, verbose: bool, list: bool) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (list) {
        for (suite.cases.items) |case| try out.print("{s}/{s}/{s}  {s}\n", .{ case.group, case.engine, case.name, case.description });
        return;
    }
    try out.writeAll("Benchmarks\n");
    const comparisons_list = try comparisons(a, suite);
    for ([_][]const u8{ "process", "startup", "snapshots", "gc" }) |group| {
        var has_group = false;
        for (suite.results.items) |r| if (std.mem.eql(u8, r.group, group)) {
            has_group = true;
            break;
        };
        if (!has_group) continue;
        if (std.mem.eql(u8, group, "process")) {
            try out.writeAll("\nProcess\n");
            try builds(out, suite, group);
            try out.print("{s:<34} {s:>7} {s:>7} {s:>12} {s:>14} {s:>12} {s:>11} {s:>12} {s:>13}\n", .{ "case", "n", "warmup", "zlua", "zlua snapshot", "Lua 5.5", "zlua/Lua", "snapshot/Lua", "snapshot/zlua" });
            for (comparisons_list) |c| {
                if (!std.mem.eql(u8, c.group, group) or !std.mem.eql(u8, c.numerator, "zlua")) continue;
                const zlua = find(suite, group, c.case, "zlua", "program").?;
                const snapshot = median(find(suite, group, c.case, "zlua_snapshot", "program"));
                const lua = median(find(suite, group, c.case, "clua", "program"));
                const plain = median(zlua);
                try out.print("{s:<34} {d:>7} {d:>7} {s:>12} {s:>14} {s:>12} {s:>11} {s:>12} {s:>13}", .{
                    c.case,
                    zlua.iterations,
                    zlua.warmup,
                    try timeText(a, plain),
                    try timeText(a, snapshot),
                    try timeText(a, lua),
                    try ratioText(a, c.ratio),
                    try ratioText(a, if (snapshot != null and lua != null) stats.ratio(snapshot.?, lua.?) else null),
                    try ratioText(a, if (snapshot != null and plain != null) stats.ratio(snapshot.?, plain.?) else null),
                });
                try status(out, zlua);
            }
        } else if (std.mem.eql(u8, group, "startup")) {
            try out.writeAll("\nStartup\n");
            try builds(out, suite, group);
            try out.print("{s:<34} {s:<9} {s:>7} {s:>7} {s:>12} {s:>12}\n", .{ "case", "engine", "n", "warmup", "startup", "first chunk" });
            for (suite.results.items) |r| {
                if (!std.mem.eql(u8, r.group, group)) continue;
                if (!std.mem.eql(u8, r.operation, "startup-total") and r.status == .benchmarked) continue;
                try out.print("{s:<34} {s:<9} {d:>7} {d:>7} {s:>12} {s:>12}", .{ r.case, r.engine, r.iterations, r.warmup, try timeText(a, median(r)), try timeText(a, median(find(suite, group, r.case, r.engine, "first-chunk"))) });
                try status(out, r);
            }
        } else if (std.mem.eql(u8, group, "gc")) {
            try out.writeAll("\nGarbage collection\n");
            try builds(out, suite, group);
            try out.print("{s:<26} {s:>7} {s:>12} {s:>12} {s:>12}\n", .{ "case", "n", "median", "p95", "max" });
            for (suite.results.items) |r| {
                if (!std.mem.eql(u8, r.group, group)) continue;
                const t = r.timing orelse continue;
                try out.print("{s:<26} {d:>7} {s:>12} {s:>12} {s:>12}\n", .{ r.case, r.iterations, try timeText(a, t.median_ns), try timeText(a, t.p95_ns), try timeText(a, t.max_ns) });
            }
        } else {
            try out.writeAll("\nSnapshots\n");
            try builds(out, suite, group);
            try out.print("{s:<26} {s:>7} {s:>7} {s:>12} {s:>12} {s:>12} {s:>9} {s:>11}\n", .{ "case", "n", "warmup", "capture", "reset", "rebuild", "speedup", "break-even" });
            for (comparisons_list) |c| {
                if (!std.mem.eql(u8, c.group, group)) continue;
                const reset = find(suite, group, c.case, "native", "reset").?;
                try out.print("{s:<26} {d:>7} {d:>7} {s:>12} {s:>12} {s:>12} {s:>9} {s:>11}", .{ c.case, reset.iterations, reset.warmup, try timeText(a, median(find(suite, group, c.case, "native", "capture"))), try timeText(a, median(reset)), try timeText(a, median(find(suite, group, c.case, "native", "rebuild"))), try ratioText(a, c.ratio), try numberText(a, c.break_even_resets) });
                try status(out, reset);
            }
            // if (find(suite, group, "bare-api-init", "native", "init")) |r| {
            //     try out.print("bare API initialization: {s} (n={d}, warmup={d})\n", .{ try timeText(a, median(r)), r.iterations, r.warmup });
            // }
        }
    }
    if (verbose) {
        try out.writeAll("\nTiming details\n");
        try out.print("{s:<34} {s:<13} {s:<14} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n", .{ "case", "engine", "operation", "median", "p95", "min", "mean", "max", "stddev" });
        for (suite.results.items) |r| {
            const t = r.timing orelse continue;
            try out.print("{s:<34} {s:<13} {s:<14} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n", .{ r.case, r.engine, r.operation, try timeText(a, t.median_ns), try timeText(a, t.p95_ns), try timeText(a, t.min_ns), try timeText(a, t.mean_ns), try timeText(a, t.max_ns), try timeText(a, t.stddev_ns) });
        }
        try out.writeAll("\nAllocation details (bytes)\n");
        try out.print("{s:<26} {s:<13} {s:<14} {s:<11} {s:>8} {s:>8} {s:>12} {s:>12} {s:>12} {s:>12}\n", .{ "case", "engine", "operation", "scope", "allocs", "resizes", "requested", "live", "peak", "runtime" });
        for (suite.results.items) |r| {
            if (r.memory_scope == .unavailable or r.status != .benchmarked) continue;
            try out.print("{s:<26} {s:<13} {s:<14} {s:<11}", .{ r.case, r.engine, r.operation, @tagName(r.memory_scope) });
            inline for (.{ "allocations", "resizes", "requested_bytes", "live_bytes", "peak_bytes", "runtime_bytes" }, 0..) |field, index| {
                const values = try a.alloc(u64, r.samples.len);
                var available = true;
                for (r.samples, values) |sample, *value| {
                    value.* = @field(sample, field) orelse {
                        available = false;
                        break;
                    };
                }
                const value = if (available) (try stats.calculate(a, values)).median_ns else null;
                const text = try numberText(a, value);
                if (index < 2) try out.print(" {s:>8}", .{text}) else try out.print(" {s:>12}", .{text});
            }
            try out.writeByte('\n');
        }
    }
    var failed: usize = 0;
    var skipped: usize = 0;
    for (suite.results.items) |r| {
        if (r.status == .failed or r.status == .timed_out) failed += 1;
        if (r.status == .skipped) skipped += 1;
    }
    try out.print("\n{d} operation results, {d} failed, {d} skipped\n", .{ suite.results.items.len, failed, skipped });
}

fn builds(out: *std.Io.Writer, suite: *const Suite, group: []const u8) !void {
    try out.writeAll("Builds:");
    for (suite.results.items, 0..) |r, index| {
        if (!std.mem.eql(u8, r.group, group)) continue;
        var seen = false;
        for (suite.results.items[0..index]) |previous| {
            if (std.mem.eql(u8, previous.group, group) and std.mem.eql(u8, previous.engine, r.engine)) {
                seen = true;
                break;
            }
        }
        if (!seen) try out.print(" {s}={s}", .{ r.engine, r.build_mode orelse "unknown" });
    }
    try out.writeByte('\n');
}

fn status(out: *std.Io.Writer, r: Result) !void {
    if (r.status != .benchmarked) try out.print("  {s}: {s}", .{ @tagName(r.status), r.reason });
    if (r.failure_sample) |index| try out.print(" ({s} sample {d})", .{ if (r.failure_during_warmup) "warmup" else "measured", index + 1 });
    try out.writeByte('\n');
}

pub fn json(allocator: std.mem.Allocator, out: *std.Io.Writer, suite: *const Suite) !void {
    const compared = try comparisons(allocator, suite);
    defer allocator.free(compared);
    const legacy = suite.legacy_process;
    try std.json.Stringify.value(.{
        .format_version = 2,
        .run = .{ .zig_version = builtin.zig_version_string, .os = @tagName(builtin.os.tag), .arch = @tagName(builtin.cpu.arch), .harness_build = @tagName(builtin.mode), .cpu = builtin.cpu.model.name, .process_order = "rotating triples: clua, zlua, zlua_snapshot", .time_unit = "ns", .memory_unit = "bytes", .median = "middle observation; average of middle two for even counts", .p95 = "nearest rank" },
        .results = suite.results.items,
        .comparisons = compared,
        .benchmarks = if (legacy == .object) legacy.object.get("benchmarks").? else std.json.Value.null,
        .counts = if (legacy == .object) legacy.object.get("counts").? else std.json.Value.null,
    }, .{ .whitespace = .indent_2 }, out);
    try out.writeByte('\n');
}

fn csvField(out: *std.Io.Writer, text: []const u8) !void {
    try out.writeByte('"');
    for (text) |c| {
        if (c == '"') try out.writeByte('"');
        try out.writeByte(c);
    }
    try out.writeByte('"');
}

pub fn csv(out: *std.Io.Writer, suite: *const Suite) !void {
    try out.writeAll("format_version,group,case,engine,operation,category,status,reason,scope,memory_scope,iterations,warmup,timeout_ms,sample,elapsed_ns,allocations,resizes,requested_bytes,live_bytes,peak_bytes,runtime_bytes,build_mode,executable,failure_sample,failure_during_warmup\n");
    for (suite.results.items) |r| {
        for (0..@max(r.samples.len, 1)) |index| {
            try out.writeAll("2");
            for ([_][]const u8{ r.group, r.case, r.engine, r.operation, r.category, @tagName(r.status), r.reason, r.scope, @tagName(r.memory_scope) }) |field| {
                try out.writeByte(',');
                try csvField(out, field);
            }
            try out.print(",{d},{d},", .{ r.iterations, r.warmup });
            if (r.timeout_ms) |v| try out.print("{d}", .{v});
            try out.writeByte(',');
            if (r.samples.len > 0) {
                try out.print("{d},{d}", .{ index, r.samples[index].elapsed_ns });
                inline for (.{ "allocations", "resizes", "requested_bytes", "live_bytes", "peak_bytes", "runtime_bytes" }) |field| {
                    try out.writeByte(',');
                    if (@field(r.samples[index], field)) |v| try out.print("{d}", .{v});
                }
            } else try out.writeAll(",,,,,,,");
            try out.writeByte(',');
            try csvField(out, r.build_mode orelse "");
            try out.writeByte(',');
            try csvField(out, r.executable orelse "");
            try out.writeByte(',');
            if (r.failure_sample) |sample| try out.print("{d}", .{sample});
            try out.print(",{s}", .{if (r.failure_during_warmup) "true" else "false"});
            try out.writeByte('\n');
        }
    }
}

pub fn writeFiles(allocator: std.mem.Allocator, io: std.Io, suite: *const Suite, json_path: ?[]const u8, csv_path: ?[]const u8) !void {
    if (json_path) |path| {
        var writer = std.Io.Writer.Allocating.init(allocator);
        defer writer.deinit();
        try json(allocator, &writer.writer, suite);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = writer.written() });
    }
    if (csv_path) |path| {
        var writer = std.Io.Writer.Allocating.init(allocator);
        defer writer.deinit();
        try csv(&writer.writer, suite);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = writer.written() });
    }
}

test "shared exports preserve samples, escaping, null metrics and failed results" {
    const a = std.testing.allocator;
    var suite = Suite.init(a);
    defer suite.deinit();
    try suite.add(.{
        .group = "startup",
        .case = "a,\"b",
        .engine = "native",
        .operation = "load",
        .scope = "load",
        .iterations = 2,
        .warmup = 0,
        .samples = &.{ .{ .elapsed_ns = 100 }, .{ .elapsed_ns = 300 } },
    });
    try suite.add(.{
        .group = "process",
        .case = "failed",
        .engine = "zlua",
        .operation = "program",
        .scope = "process",
        .iterations = 2,
        .warmup = 0,
        .status = .failed,
        .reason = "later sample",
    });
    var writer = std.Io.Writer.Allocating.init(a);
    defer writer.deinit();
    try json(a, &writer.writer, &suite);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, writer.written(), .{});
    defer parsed.deinit();
    const rows = parsed.value.object.get("results").?.array.items;
    try std.testing.expectEqual(@as(i64, 200), rows[0].object.get("timing").?.object.get("median_ns").?.integer);
    try std.testing.expect(rows[0].object.get("samples").?.array.items[0].object.get("allocations").? == .null);
    try std.testing.expect(rows[1].object.get("timing").? == .null);
    var csv_writer = std.Io.Writer.Allocating.init(a);
    defer csv_writer.deinit();
    try csv(&csv_writer.writer, &suite);
    try std.testing.expect(std.mem.indexOf(u8, csv_writer.written(), "\"a,\"\"b\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, csv_writer.written(), ",0,100,,,,,,,") != null);
}

test "process report compares all three engines and omits ratios for failures" {
    const a = std.testing.allocator;
    var suite = Suite.init(a);
    defer suite.deinit();
    for ([_][]const u8{ "clua", "zlua", "zlua_snapshot" }, [_]u64{ 100, 200, 300 }) |engine, time| {
        for ([_]results.Status{ .benchmarked, .failed }) |state| {
            try suite.add(.{
                .group = "process",
                .case = @tagName(state),
                .engine = engine,
                .operation = "program",
                .scope = "process",
                .iterations = 1,
                .warmup = 0,
                .status = state,
                .samples = &.{.{ .elapsed_ns = time }},
            });
        }
    }
    const compared = try comparisons(a, &suite);
    defer a.free(compared);
    try std.testing.expectEqual(@as(usize, 6), compared.len);
    for (compared) |c| {
        if (std.mem.eql(u8, c.case, "failed")) {
            try std.testing.expect(c.ratio == null);
        } else {
            const expected: f64 = if (std.mem.eql(u8, c.numerator, "zlua")) 2 else if (std.mem.eql(u8, c.denominator, "clua")) 3 else 1.5;
            try std.testing.expectEqual(expected, c.ratio.?);
        }
    }
    var out = std.Io.Writer.Allocating.init(a);
    defer out.deinit();
    try human(a, &out.writer, &suite, false, false);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "zlua snapshot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "snapshot/Lua") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "snapshot/zlua") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "300 ns") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "benchmarked"));
}
