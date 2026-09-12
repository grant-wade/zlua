const std = @import("std");
const default_bench_root = "tests/bench";
pub const Family = enum { process, startup, snapshots, gc, all };
pub const Options = struct {
    family: Family = .all,
    verbose: bool = false,
    zlua_build: ?[]const u8 = null,
    clua_build: ?[]const u8 = null,
    c_build: ?[]const u8 = null,
    clua_c: ?[]const u8 = null,
    bench_root: []const u8 = default_bench_root,
    selectors: []const []const u8 = &.{},
    clua: ?[]const u8 = null,
    zlua: ?[]const u8 = null,
    list: bool = false,
    iterations: ?usize = null,
    warmup: ?usize = null,
    timeout_ms: ?u64 = null,
    category: ?[]const u8 = null,
    json_path: ?[]const u8 = null,
    csv_path: ?[]const u8 = null,
    debug_errors: bool = false,

    pub fn matches(self: Options, group: []const u8, engine: []const u8, name: []const u8) bool {
        if (self.category) |category| if (!std.mem.eql(u8, category, group)) return false;
        if (self.selectors.len == 0) return true;
        for (self.selectors) |selector| {
            var buffer: [512]u8 = undefined;
            const full = std.fmt.bufPrint(&buffer, "{s}/{s}/{s}", .{ group, engine, name }) catch continue;
            if (std.mem.eql(u8, selector, name) or std.mem.eql(u8, selector, engine) or std.mem.eql(u8, selector, group) or
                std.mem.eql(u8, selector, full) or (std.mem.startsWith(u8, full, selector) and full.len > selector.len and full[selector.len] == '/')) return true;
        }
        return false;
    }

    pub fn deinit(self: Options, allocator: std.mem.Allocator) void {
        allocator.free(self.selectors);
    }
};

pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Options {
    var options: Options = .{};
    var selectors = std.ArrayList([]const u8).empty;
    errdefer selectors.deinit(allocator);

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "--family=")) {
            options.family = std.meta.stringToEnum(Family, arg[9..]) orelse return error.InvalidOptionValue;
        } else if (std.mem.startsWith(u8, arg, "--zlua-build=")) {
            options.zlua_build = arg[13..];
        } else if (std.mem.startsWith(u8, arg, "--clua-build=")) {
            options.clua_build = arg[13..];
        } else if (std.mem.startsWith(u8, arg, "--c-build=")) {
            options.c_build = arg[10..];
        } else if (std.mem.eql(u8, arg, "--clua-c")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.clua_c = args[index];
            options.c_build = null;
        } else if (std.mem.eql(u8, arg, "--list")) {
            options.list = true;
        } else if (std.mem.eql(u8, arg, "--debug-errors")) {
            options.debug_errors = true;
        } else if (std.mem.eql(u8, arg, "--no-warmup")) {
            options.warmup = 0;
        } else if (std.mem.eql(u8, arg, "--clua")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.clua = args[index];
            options.clua_build = null;
        } else if (std.mem.startsWith(u8, arg, "--clua=")) {
            options.clua = arg[7..];
            options.clua_build = null;
        } else if (std.mem.eql(u8, arg, "--zlua")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.zlua = args[index];
            options.zlua_build = null;
        } else if (std.mem.startsWith(u8, arg, "--zlua=")) {
            options.zlua = arg[7..];
            options.zlua_build = null;
        } else if (std.mem.eql(u8, arg, "--iterations")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.iterations = try parsePositiveUsize(args[index]);
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            options.iterations = try parsePositiveUsize(arg[13..]);
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.warmup = try std.fmt.parseInt(usize, args[index], 10);
        } else if (std.mem.startsWith(u8, arg, "--warmup=")) {
            options.warmup = try std.fmt.parseInt(usize, arg[9..], 10);
        } else if (std.mem.eql(u8, arg, "--timeout-ms")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.timeout_ms = try parsePositiveU64(args[index]);
        } else if (std.mem.startsWith(u8, arg, "--timeout-ms=")) {
            options.timeout_ms = try parsePositiveU64(arg[13..]);
        } else if (std.mem.eql(u8, arg, "--category")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.category = args[index];
        } else if (std.mem.startsWith(u8, arg, "--category=")) {
            options.category = arg[11..];
        } else if (std.mem.eql(u8, arg, "--json")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.json_path = args[index];
        } else if (std.mem.startsWith(u8, arg, "--json=")) {
            options.json_path = arg[7..];
        } else if (std.mem.eql(u8, arg, "--csv")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.csv_path = args[index];
        } else if (std.mem.startsWith(u8, arg, "--csv=")) {
            options.csv_path = arg[6..];
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownOption;
        } else {
            try selectors.append(allocator, arg);
        }
    }

    options.selectors = try selectors.toOwnedSlice(allocator);
    return options;
}

pub fn parsePositiveUsize(value: []const u8) !usize {
    const parsed = try std.fmt.parseInt(usize, value, 10);
    if (parsed == 0) return error.InvalidOptionValue;
    return parsed;
}

pub fn parsePositiveU64(value: []const u8) !u64 {
    const parsed = try std.fmt.parseInt(u64, value, 10);
    if (parsed == 0) return error.InvalidOptionValue;
    return parsed;
}

test "argument parser accepts benchmark overrides" {
    const args = [_][]const u8{ "vm/arithmetic", "--iterations=3", "--warmup", "0", "--timeout-ms=10", "--category=vm", "--json", "bench.json", "--csv=bench.csv", "--debug-errors" };
    const options = try parseArgs(std.testing.allocator, &args);
    defer options.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), options.selectors.len);
    try std.testing.expectEqualStrings("vm/arithmetic", options.selectors[0]);
    try std.testing.expectEqual(@as(usize, 3), options.iterations.?);
    try std.testing.expectEqual(@as(usize, 0), options.warmup.?);
    try std.testing.expectEqual(@as(u64, 10), options.timeout_ms.?);
    try std.testing.expectEqualStrings("bench.json", options.json_path.?);
    try std.testing.expectEqualStrings("bench.csv", options.csv_path.?);
    try std.testing.expect(options.debug_errors);
}

test "selectors match case and qualified group paths" {
    var options: Options = .{ .selectors = &.{"startup/native"} };
    try std.testing.expect(options.matches("startup", "native", "full"));
    try std.testing.expect(!options.matches("startup", "clua", "full"));
    options.selectors = &.{"callbacks"};
    try std.testing.expect(options.matches("snapshots", "native", "callbacks"));
    try std.testing.expect(!options.matches("snapshots", "native", "modules"));
}

test "overriding an executable invalidates its advertised build" {
    const options = try parseArgs(std.testing.allocator, &.{ "--zlua", "built", "--zlua-build=ReleaseFast", "--zlua=external" });
    defer options.deinit(std.testing.allocator);
    try std.testing.expect(options.zlua_build == null);
    try std.testing.expectEqualStrings("external", options.zlua.?);
}

test "invalid and missing numeric arguments are rejected" {
    try std.testing.expectError(error.InvalidOptionValue, parseArgs(std.testing.allocator, &.{"--iterations=0"}));
    try std.testing.expectError(error.MissingOptionValue, parseArgs(std.testing.allocator, &.{"--warmup"}));
    try std.testing.expectError(error.UnknownOption, parseArgs(std.testing.allocator, &.{"--unknown"}));
}
