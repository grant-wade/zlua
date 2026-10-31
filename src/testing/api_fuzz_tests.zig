const std = @import("std");
const api = @import("../root.zig");
const a = std.testing.allocator;
const Smith = std.testing.Smith;

const limits: api.Options = .{ .limits = .{ .max_memory = 64 << 20, .max_instructions = 200_000 } };

fn loadSource(source: []const u8) !void {
    var lua = try api.State.init(a, limits);
    defer lua.deinit();
    var function = lua.loadString(source, .{ .name = "=fuzz" }) catch |err| switch (err) {
        error.LuaError, error.OutOfMemory => return,
        else => return err,
    };
    function.deinit();
}

const bytecode_seeds = [_][]const u8{
    "return 1 + 2 * 3",
    "local t = {} for i = 1, 10 do t[i] = i * i end return #t, t[3]",
    "local function f(...) local a, b = ... return select('#', ...), a, b end return f(1, nil, 3)",
    "local s = 0 for k, v in pairs({a = 1, b = 2}) do s = s + v end return s",
    "local x <close> = nil local up = 1 local function g() up = up + 1 return up end return g(), g()",
    "goto skip ::back:: do return 'back' end ::skip:: if true then goto back end",
    "return ('x'):rep(3) .. 1 .. 2.5, -7 // 2, 7 % -3, 1 << 62, ~0, 2^0.5",
    "local co = coroutine.wrap(function(a) local b = coroutine.yield(a + 1) return b * 2 end) return co(1), co(5)",
};

const Mutation = struct { offset: usize, byte: u8 };

fn runMutatedBytecode(seed: usize, mutations: []const Mutation, truncate: usize) !void {
    var lua = try api.State.init(a, limits);
    defer lua.deinit();

    var original = try lua.loadString(bytecode_seeds[seed % bytecode_seeds.len], .{ .name = "=seed" });
    const dump = try original.dumpBytecode(.{ .strip_debug = seed % 2 == 1 });
    original.deinit();
    defer lua.allocator().free(dump);

    const bytes = try a.dupe(u8, dump[0 .. dump.len - @min(truncate, dump.len)]);
    defer a.free(bytes);
    for (mutations) |mutation| {
        if (bytes.len == 0) break;
        bytes[mutation.offset % bytes.len] = mutation.byte;
    }

    var function = lua.loadBytecode(bytes, .{}) catch |err| switch (err) {
        error.LuaError, error.OutOfMemory => return,
        else => return err,
    };
    defer function.deinit();
    var result = function.protectedCallWith(.{}, void, .{ .max_instructions = 20_000 }) catch |err| switch (err) {
        error.OutOfMemory, error.Interrupted, error.LuaExit => return,
        else => return err,
    };
    if (result == .lua_error) result.lua_error.deinit();
}

const string_library_chunk =
    \\local s, p, f = ...
    \\pcall(string.find, s, p)
    \\pcall(string.match, s, p)
    \\pcall(string.gsub, s, p, "%0%1")
    \\pcall(function() for _ in string.gmatch(s, p) do end end)
    \\pcall(string.format, f, 1, -2.5, s, 3)
    \\pcall(string.packsize, f)
    \\pcall(string.unpack, f, s)
    \\pcall(function() return string.unpack(f, string.pack(f, 1, 2, 3, 4, 5)) end)
;

fn tooManyQuantifiers(pattern: []const u8) bool {
    var count: usize = 0;
    for (pattern) |byte| {
        if (std.mem.indexOfScalar(u8, "*+-?", byte) != null) count += 1;
    }
    return count > 4;
}

fn runStringLibrary(subject: []const u8, pattern: []const u8, format: []const u8) !void {
    if (tooManyQuantifiers(pattern)) return;
    var lua = try api.State.init(a, limits);
    defer lua.deinit();
    var function = try lua.loadString(string_library_chunk, .{ .name = "=fuzz" });
    defer function.deinit();
    var result = function.protectedCall(.{ subject, pattern, format }, void) catch |err| switch (err) {
        error.OutOfMemory => return,
        else => return err,
    };
    if (result == .lua_error) result.lua_error.deinit();
}

test "fuzz source loading" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *Smith) !void {
            var buffer: [2048]u8 = undefined;
            try loadSource(buffer[0..smith.slice(&buffer)]);
        }
    }.testOne, .{});
}

test "fuzz binary chunk verification" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *Smith) !void {
            var mutations: [8]Mutation = undefined;
            const count = smith.valueRangeAtMost(u8, 0, mutations.len);
            for (mutations[0..count]) |*mutation| mutation.* = .{ .offset = smith.value(u32), .byte = smith.value(u8) };
            try runMutatedBytecode(smith.value(u8), mutations[0..count], smith.valueRangeAtMost(u8, 0, 16));
        }
    }.testOne, .{});
}

test "fuzz string library inputs" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *Smith) !void {
            var subject: [64]u8 = undefined;
            var pattern: [24]u8 = undefined;
            var format: [24]u8 = undefined;
            const subject_len = smith.slice(&subject);
            const pattern_len = smith.slice(&pattern);
            const format_len = smith.slice(&format);
            try runStringLibrary(subject[0..subject_len], pattern[0..pattern_len], format[0..format_len]);
        }
    }.testOne, .{});
}

fn repeat(comptime text: []const u8, comptime count: usize) []const u8 {
    comptime {
        var out: [text.len * count]u8 = undefined;
        for (0..count) |index| @memcpy(out[index * text.len ..][0..text.len], text);
        const final = out;
        return &final;
    }
}

test "fuzz targets accept seed inputs" {
    const sources = comptime [_][]const u8{
        "",
        "local x <const> = 1; x = 2",
        "return " ++ repeat("(", 300) ++ "1" ++ repeat(")", 300),
        "goto l1; local a ::l1::",
        "global none; x = 1",
        "return 0x1p99999999999, 0xe03" ++ repeat("0", 64) ++ "p-4000, '\\u{7FFFFFFF}'",
        "--[==[ unfinished",
        "\x1bLua",
    };
    for (sources) |source| try loadSource(source);

    for (0..bytecode_seeds.len * 2) |seed| {
        try runMutatedBytecode(seed, &.{}, 0);
        try runMutatedBytecode(seed, &.{ .{ .offset = 12, .byte = 0xff }, .{ .offset = 40, .byte = 0 } }, 0);
        try runMutatedBytecode(seed, &.{.{ .offset = seed * 7, .byte = 0x80 }}, 3);
    }

    try runStringLibrary("hello world", "(%w+) (%w+)", "%5.2f|%q");
    try runStringLibrary("aaaa", "%b()%f[%a]", "<i4 >d s1");
    try runStringLibrary("x", "[%", "%");
    try runStringLibrary("(((x)))", "%b()", "!17 Xi16");
    try runStringLibrary("abc", "(()(%1))", "c99999999999");
}

const generators = @import("generators.zig");
const Picker = generators.Picker;

const sandbox_limits: api.Options = .{
    .limits = .{ .max_memory = 16 << 20, .max_instructions = 4_000_000, .max_finalizer_instructions = 20_000, .max_output_bytes = 1 << 16 },
};

fn runGenerated(source: []const u8, options: api.Options) !void {
    var buffer: [256]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&buffer);
    var configured = options;
    configured.capabilities.io.stdout = &sink.writer;
    configured.capabilities.io.stderr = &sink.writer;
    var lua = try api.State.init(a, configured);
    defer lua.deinit();
    run: {
        var function = lua.loadString(source, .{ .name = "=generated" }) catch break :run;
        defer function.deinit();
        var result = function.protectedCallWith(.{}, void, .{ .max_instructions = 200_000 }) catch break :run;
        if (result == .lua_error) result.lua_error.deinit();
    }
    try expectUsable(&lua);
}

fn expectUsable(lua: *api.State) !void {
    lua.resetInstructionBudget();
    lua.resetOutputLimit();
    lua.clearInterrupt();
    var probe = lua.loadString("return 1 + 1", .{}) catch |err| switch (err) {
        error.LuaError, error.OutOfMemory => return,
        else => return err,
    };
    defer probe.deinit();
    var result = probe.protectedCall(.{}, i64) catch |err| switch (err) {
        error.OutOfMemory => return,
        else => return err,
    };
    switch (result) {
        .ok => |value| try std.testing.expectEqual(@as(i64, 2), value),
        .lua_error => |*lua_error| lua_error.deinit(),
    }
}

fn runProgram(picker: Picker) !void {
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try generators.writeProgram(picker, &out.writer);
    try runGenerated(out.written(), sandbox_limits);
}

fn runLibraryCalls(picker: Picker) !void {
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try generators.writeLibraryCalls(picker, &out.writer);
    try runGenerated(out.written(), sandbox_limits);
}

fn runFormatText(picker: Picker) !void {
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try generators.writeFormatText(picker, &out.writer);

    var lua = try api.State.init(a, sandbox_limits);
    defer lua.deinit();
    var function = try lua.loadString(
        \\local text = ...
        \\for _, format in ipairs({json, toml, msgpack, csv}) do
        \\  local ok, value = pcall(format.read, text)
        \\  if ok then
        \\    local written, bytes = pcall(format.write, value)
        \\    if written then pcall(format.read, bytes) end
        \\  end
        \\end
    , .{ .name = "=formats" });
    defer function.deinit();
    var result = function.protectedCallWith(.{out.written()}, void, .{ .max_instructions = 200_000 }) catch |err| switch (err) {
        error.OutOfMemory => return,
        else => return err,
    };
    if (result == .lua_error) result.lua_error.deinit();
    try expectUsable(&lua);
}

var generated_chunks_loaded: usize = 0;

fn runChunk(picker: Picker) !void {
    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(a);
    try generators.appendChunk(picker, a, &bytes);

    var options = sandbox_limits;
    options.binary_chunks = true;
    var lua = try api.State.init(a, options);
    defer lua.deinit();
    var function = lua.loadBytecode(bytes.items, .{}) catch |err| switch (err) {
        error.LuaError, error.OutOfMemory => return,
        else => return err,
    };
    defer function.deinit();
    generated_chunks_loaded += 1;
    var result = function.protectedCallWith(.{ @as(i64, 1), @as(f64, 2.5), "s" }, void, .{ .max_instructions = 20_000 }) catch |err| switch (err) {
        error.OutOfMemory, error.Interrupted, error.LuaExit => return,
        else => return err,
    };
    if (result == .lua_error) result.lua_error.deinit();
    try expectUsable(&lua);
}

test "fuzz generated programs" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *Smith) !void {
            try runProgram(Picker.fromSmith(smith));
        }
    }.testOne, .{});
}

test "fuzz library calls with hostile arguments" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *Smith) !void {
            try runLibraryCalls(Picker.fromSmith(smith));
        }
    }.testOne, .{});
}

test "fuzz data format readers" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *Smith) !void {
            try runFormatText(Picker.fromSmith(smith));
        }
    }.testOne, .{});
}

test "fuzz verified binary chunks" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *Smith) !void {
            try runChunk(Picker.fromSmith(smith));
        }
    }.testOne, .{});
}

fn sweep(comptime run: fn (Picker) anyerror!void, seed: u64, count: usize) !void {
    var prng: std.Random.DefaultPrng = .init(seed);
    var random = prng.random();
    for (0..count) |_| try run(Picker.fromRandom(&random));
}

fn runTimezone(picker: Picker) !void {
    const timezone = @import("../runtime/timezone.zig");
    var bytes: [512]u8 = undefined;
    const length = picker.below(bytes.len);
    for (bytes[0..length]) |*byte| byte.* = @intCast(picker.below(256));
    if (picker.chance(70)) {
        const header = "TZif2\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";
        @memcpy(bytes[0..@min(header.len, length)], header[0..@min(header.len, length)]);
    }
    const timestamps = [_]i64{ 0, 1 << 32, -(1 << 40), std.math.maxInt(i64), std.math.minInt(i64) };
    var zone = timezone.Zone.parseTzif(a, bytes[0..length]) catch null;
    if (zone) |*parsed| {
        defer parsed.deinit();
        for (timestamps) |timestamp| _ = parsed.offsetAt(timestamp);
    }
    const rules = [_][]const u8{ "<", "UTC", "EST5EDT", "EST5EDT,M3.2.0,M11.1.0", "A-99:99:99B,J366/999,0/-999", "X1,M13.9.9,M0.0.0", "AAA24BBB,J0,J9999", "<+03>-3<+04>,M1.1.1/-168,M12.5.6/167" };
    if (timezone.PosixRule.parse(picker.pick([]const u8, &rules))) |rule| {
        for (timestamps) |timestamp| _ = rule.offsetAt(timestamp);
    }
}

test "timezone parsers accept any bytes" {
    try sweep(runTimezone, 5, 3000);
}

test "generated programs keep the state usable" {
    try sweep(runProgram, 1, 400);
}

test "library calls with hostile arguments keep the state usable" {
    try sweep(runLibraryCalls, 2, 1500);
}

test "data format readers keep the state usable" {
    try sweep(runFormatText, 3, 1500);
}

test "verified binary chunks keep the state usable" {
    generated_chunks_loaded = 0;
    try sweep(runChunk, 4, 1500);
    try std.testing.expect(generated_chunks_loaded == 1500);
}
