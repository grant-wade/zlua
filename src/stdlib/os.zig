const std = @import("std");
const builtin = @import("builtin");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const host = @import("../runtime/host.zig");
const timezone = @import("../runtime/timezone.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;

pub fn time(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count >= 1 and runtime.argValue(state, thread, op, 0) != .nil) {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = try tableToTime(state, runtime.argValue(state, thread, op, 0)) }});
    } else {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = try state.currentTime() }});
    }
}

pub fn clock(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .number = try state.cpuTime() }});
}

pub fn date(state: *State, thread: *Thread, op: bytecode.Call) !void {
    var format = if (op.arg_count >= 1 and runtime.argValue(state, thread, op, 0) != .nil)
        try state.expectArgumentString(thread, op, "os.date", 0)
    else
        "%c";
    const when = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil)
        try state.argumentInteger(thread, op, "os.date", 1)
    else
        try state.currentTime();

    const utc = format.len != 0 and format[0] == '!';
    if (utc) format = format[1..];
    const offset: timezone.LocalOffset = if (utc) .{ .name = "UTC" } else try state.localOffset(when);
    const parts = brokenDownTime(when, offset) orelse return state.failLibrary("date result cannot be represented in this installation");
    if (std.mem.eql(u8, format, "*t")) {
        const value = try state.newTableWithHints(0, 9);
        try setDateFields(state, value.table, parts);
        try state.returnValues(thread, op.base, op.return_count, &.{value});
        return;
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    try formatDate(state, &out, format, parts);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.intern(out.items) }});
}

pub fn exit(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const status = runtime.argValue(state, thread, op, 0);
    const code: i32 = switch (status) {
        .boolean => |success| if (success) 0 else 1,
        .nil => 0,
        else => @truncate(try state.argumentInteger(thread, op, "os.exit", 0)),
    };
    const close = op.arg_count >= 2 and runtime.truthy(runtime.argValue(state, thread, op, 1));
    try state.requestExit(code, close);
    return error.LuaExit;
}

pub fn remove(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "os.remove", 0);
    state.fsRemovePath(path, false) catch |err| return fileFailure(state, thread, op, path, err);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn rename(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const old_path = try state.expectArgumentString(thread, op, "os.rename", 0);
    const new_path = try state.expectArgumentString(thread, op, "os.rename", 1);
    state.fsRenamePath(old_path, new_path) catch |err| return fileFailure(state, thread, op, null, err);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

/// Returns `nil, "[path: ]message", errno` like `luaL_fileresult`.
pub fn fileFailure(state: *State, thread: *Thread, op: bytecode.Call, path: ?[]const u8, err: anyerror) !void {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    const info = host.fileError(err);
    const message = if (path) |name|
        try std.fmt.allocPrint(state.allocator, "{s}: {s}", .{ name, info.message })
    else
        try state.allocator.dupe(u8, info.message);
    defer state.allocator.free(message);
    try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern(message) }, .{ .integer = info.errno } });
}

/// Like `mkstemp` in PUC's `os.tmpname`, creates an empty file with an
/// unpredictable name and returns the name; the caller removes the file.
pub fn tmpname(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try createTempFile(state) orelse return state.fail("unable to generate a unique filename");
    defer state.allocator.free(name);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.intern(name) }});
}

const temp_name_prefix = "lua_";
const temp_name_random_len = 6;
const temp_name_attempts = 100;

fn createTempFile(state: *State) !?[]u8 {
    const directory: ?[]const u8 = switch (state.options.filesystem) {
        .host_cwd => tempDirectory(state),
        else => null,
    };
    var attempt: usize = 0;
    while (attempt < temp_name_attempts) : (attempt += 1) {
        var random: [temp_name_random_len]u8 = undefined;
        randomNameBytes(state, &random);
        const name = if (directory) |dir|
            try std.fmt.allocPrint(state.allocator, "{s}{c}" ++ temp_name_prefix ++ "{s}", .{ std.mem.trimEnd(u8, dir, "/\\"), std.fs.path.sep, &random })
        else
            try std.fmt.allocPrint(state.allocator, temp_name_prefix ++ "{s}", .{&random});
        state.fsCreateFileExclusive(name) catch |err| {
            state.allocator.free(name);
            switch (err) {
                error.OutOfMemory => return err,
                error.PathAlreadyExists => continue,
                else => return null,
            }
        };
        return name;
    }
    return null;
}

fn tempDirectory(state: *State) []const u8 {
    const variables: []const []const u8 = if (builtin.os.tag == .windows) &.{ "TMP", "TEMP", "USERPROFILE" } else &.{"TMPDIR"};
    for (variables) |name| {
        if (state.getenv(name)) |value| if (value.len != 0) return value;
    }
    return if (builtin.os.tag == .windows) "C:\\Windows\\Temp" else "/tmp";
}

var temp_name_counter = std.atomic.Value(u32).init(0);

fn randomNameBytes(state: *State, out: []u8) void {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    var bytes: [16]u8 = undefined;
    if (state.options.io) |io| {
        io.random(&bytes);
    } else {
        const count = temp_name_counter.fetchAdd(1, .monotonic);
        var hasher = std.hash.Wyhash.init(count);
        const identity = @intFromPtr(state);
        hasher.update(std.mem.asBytes(&identity));
        hasher.update(std.mem.asBytes(&state.instruction_count));
        hasher.update(std.mem.asBytes(&state.file_generation));
        const first = hasher.final();
        const second = std.hash.Wyhash.hash(first, std.mem.asBytes(&count));
        @memcpy(bytes[0..8], std.mem.asBytes(&first));
        @memcpy(bytes[8..16], std.mem.asBytes(&second));
    }
    for (out, 0..) |*byte, index| byte.* = alphabet[bytes[index % bytes.len] % alphabet.len];
}

pub fn difftime(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const t2 = try state.argumentInteger(thread, op, "os.difftime", 0);
    const t1 = try state.argumentInteger(thread, op, "os.difftime", 1);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .number = @as(f64, @floatFromInt(t2)) - @as(f64, @floatFromInt(t1)) }});
}

pub fn getenv(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentString(thread, op, "os.getenv", 0);
    const value = if (state.getenv(name)) |env| Value{ .string = try state.intern(env) } else Value.nil;
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}

pub fn setlocale(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const locale = if (op.arg_count >= 1 and runtime.argValue(state, thread, op, 0) != .nil)
        try state.expectArgumentString(thread, op, "os.setlocale", 0)
    else
        "C";
    const value = if (std.mem.eql(u8, locale, "C")) Value{ .string = try state.intern("C") } else Value.nil;
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}

pub fn execute(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0 or runtime.argValue(state, thread, op, 0) == .nil) {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = state.processEnabled() }});
        return;
    }
    const command = try state.expectArgumentString(thread, op, "os.execute", 0);
    try returnProcessResult(state, thread, op, try state.executeProcess(command));
}

/// Returns `true|nil, "exit"|"signal", code` like `luaL_execresult`.
pub fn returnProcessResult(state: *State, thread: *Thread, op: bytecode.Call, result: host.ProcessResult) !void {
    const status = try state.intern(switch (result.status) {
        .exit => "exit",
        .signal => "signal",
    });
    const success: Value = if (result.status == .exit and result.code == 0) .{ .boolean = true } else .nil;
    try state.returnValues(thread, op.base, op.return_count, &.{ success, .{ .string = status }, .{ .integer = result.code } });
}

pub const DateParts = struct {
    year: i64,
    month: u8,
    day: u8,
    hour: u8,
    min: u8,
    sec: u8,
    /// Day of the year, 1-366.
    yday: u16,
    /// Day of the week, Sunday = 0.
    wday: u8,
    is_dst: bool,
    offset: i32,
    zone: ?[]const u8,
};

/// Breaks a Unix timestamp into local calendar fields; null when the year
/// does not fit C's `struct tm`.
pub fn brokenDownTime(timestamp: i64, offset: timezone.LocalOffset) ?DateParts {
    const local = std.math.add(i64, timestamp, offset.offset) catch return null;
    const days = @divFloor(local, timezone.seconds_per_day);
    const seconds: u32 = @intCast(@mod(local, timezone.seconds_per_day));
    const civil = timezone.civilFromDays(days);
    if (civil.year - 1900 < std.math.minInt(i32) or civil.year - 1900 > std.math.maxInt(i32)) return null;
    return .{
        .year = civil.year,
        .month = civil.month,
        .day = civil.day,
        .hour = @intCast(seconds / 3600),
        .min = @intCast(seconds / 60 % 60),
        .sec = @intCast(seconds % 60),
        .yday = @intCast(days - timezone.daysFromCivil(civil.year, 1, 1) + 1),
        .wday = timezone.weekday(days),
        .is_dst = offset.is_dst,
        .offset = offset.offset,
        .zone = offset.name,
    };
}

fn setDateFields(state: *State, table: *runtime.Table, parts: DateParts) !void {
    try setField(state, table, "year", .{ .integer = parts.year });
    try setField(state, table, "month", .{ .integer = parts.month });
    try setField(state, table, "day", .{ .integer = parts.day });
    try setField(state, table, "hour", .{ .integer = parts.hour });
    try setField(state, table, "min", .{ .integer = parts.min });
    try setField(state, table, "sec", .{ .integer = parts.sec });
    try setField(state, table, "yday", .{ .integer = parts.yday });
    try setField(state, table, "wday", .{ .integer = @as(i64, parts.wday) + 1 });
    try setField(state, table, "isdst", .{ .boolean = parts.is_dst });
}

fn setField(state: *State, table: *runtime.Table, name: []const u8, value: Value) !void {
    try state.setTableRaw(table, .{ .string = try state.intern(name) }, value);
}

fn tableToTime(state: *State, value: Value) !i64 {
    const table = switch (value) {
        .table => |table| table,
        else => return state.failArgumentType("os.time", 1, "table", value),
    };
    const year = try dateField(state, table, "year", null, 1900);
    const month = try dateField(state, table, "month", null, 1);
    const day = try dateField(state, table, "day", null, 0);
    const hour = try dateField(state, table, "hour", 12, 0);
    const min = try dateField(state, table, "min", 0, 0);
    const sec = try dateField(state, table, "sec", 0, 0);
    const isdst_value = table.get(.{ .string = "isdst" });
    const is_dst: ?bool = if (isdst_value == .nil) null else runtime.truthy(isdst_value);

    const months = year * 12 + (month - 1);
    const days = timezone.daysFromCivil(@divFloor(months, 12), @mod(months, 12) + 1, 1) + (day - 1);
    const local = days * timezone.seconds_per_day + hour * 3600 + min * 60 + sec;
    const timestamp = try state.localToUtc(local, is_dst);
    const parts = brokenDownTime(timestamp, try state.localOffset(timestamp)) orelse
        return state.failLibrary("time result cannot be represented in this installation");
    try setDateFields(state, table, parts);
    if (timestamp == -1) return state.failLibrary("time result cannot be represented in this installation");
    return timestamp;
}

fn dateField(state: *State, table: *runtime.Table, comptime name: []const u8, default: ?i64, comptime delta: i64) !i64 {
    const value = table.get(.{ .string = name });
    const integer = runtime.coerceToInteger(value) orelse {
        if (value != .nil) return state.failLibrary("field '" ++ name ++ "' is not an integer");
        return default orelse state.failLibrary("field '" ++ name ++ "' missing in date table");
    };
    const in_bounds = if (integer >= 0)
        integer - delta <= std.math.maxInt(i32)
    else
        @as(i64, std.math.minInt(i32)) + delta <= integer;
    if (!in_bounds) return state.failLibrary("field '" ++ name ++ "' is out-of-bound");
    return integer;
}

const weekday_names = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
const month_names = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };

const single_conversions = "aAbBcCdDeFgGhHIjmMnprRStTuUVwWxXyYzZ%";
const double_conversions = [_][]const u8{ "Ec", "EC", "Ex", "EX", "Ey", "EY", "Od", "Oe", "OH", "OI", "Om", "OM", "OS", "Ou", "OU", "OV", "Ow", "OW", "Oy" };

fn formatDate(state: *State, out: *std.ArrayList(u8), format: []const u8, parts: DateParts) !void {
    var index: usize = 0;
    while (index < format.len) : (index += 1) {
        if (format[index] != '%') {
            try out.append(state.allocator, format[index]);
            continue;
        }
        index += 1;
        const rest = format[index..];
        if (rest.len >= 2 and (rest[0] == 'E' or rest[0] == 'O')) {
            for (double_conversions) |conversion| {
                if (std.mem.eql(u8, rest[0..2], conversion)) {
                    index += 1;
                    try appendConversion(state, out, rest[1], parts);
                    break;
                }
            } else return invalidConversion(state, rest[0..@min(rest.len, 2)]);
            continue;
        }
        if (rest.len == 0 or std.mem.indexOfScalar(u8, single_conversions, rest[0]) == null) {
            return invalidConversion(state, rest[0..@min(rest.len, 1)]);
        }
        try appendConversion(state, out, rest[0], parts);
    }
}

fn invalidConversion(state: *State, conversion: []const u8) anyerror {
    const message = try std.fmt.allocPrint(state.allocator, "invalid conversion specifier '%{s}'", .{conversion});
    defer state.allocator.free(message);
    return state.failArgumentMessage("os.date", 1, try state.intern(message));
}

fn appendConversion(state: *State, out: *std.ArrayList(u8), conversion: u8, parts: DateParts) anyerror!void {
    const allocator = state.allocator;
    const hour12: u8 = if (parts.hour % 12 == 0) 12 else parts.hour % 12;
    switch (conversion) {
        '%' => try out.append(allocator, '%'),
        'n' => try out.append(allocator, '\n'),
        't' => try out.append(allocator, '\t'),
        'a' => try out.appendSlice(allocator, weekday_names[parts.wday][0..3]),
        'A' => try out.appendSlice(allocator, weekday_names[parts.wday]),
        'b', 'h' => try out.appendSlice(allocator, month_names[parts.month - 1][0..3]),
        'B' => try out.appendSlice(allocator, month_names[parts.month - 1]),
        'c' => {
            try appendConversion(state, out, 'a', parts);
            try out.append(allocator, ' ');
            try appendConversion(state, out, 'b', parts);
            try out.append(allocator, ' ');
            try appendConversion(state, out, 'e', parts);
            try out.append(allocator, ' ');
            try appendConversion(state, out, 'T', parts);
            try out.append(allocator, ' ');
            try appendConversion(state, out, 'Y', parts);
        },
        'C' => try appendPadded(allocator, out, @divFloor(parts.year, 100), 2),
        'd' => try appendPadded(allocator, out, parts.day, 2),
        'D', 'x' => try appendSequence(state, out, "%m/%d/%y", parts),
        'e' => try runtime.appendFmt(allocator, out, "{d:>2}", .{parts.day}),
        'F' => try appendSequence(state, out, "%Y-%m-%d", parts),
        'g' => try appendPadded(allocator, out, @mod(isoWeekYear(parts).year, 100), 2),
        'G' => try runtime.appendFmt(allocator, out, "{d}", .{isoWeekYear(parts).year}),
        'H' => try appendPadded(allocator, out, parts.hour, 2),
        'I' => try appendPadded(allocator, out, hour12, 2),
        'j' => try appendPadded(allocator, out, parts.yday, 3),
        'm' => try appendPadded(allocator, out, parts.month, 2),
        'M' => try appendPadded(allocator, out, parts.min, 2),
        'p' => try out.appendSlice(allocator, if (parts.hour < 12) "AM" else "PM"),
        'r' => try appendSequence(state, out, "%I:%M:%S %p", parts),
        'R' => try appendSequence(state, out, "%H:%M", parts),
        'S' => try appendPadded(allocator, out, parts.sec, 2),
        'T', 'X' => try appendSequence(state, out, "%H:%M:%S", parts),
        'u' => try runtime.appendFmt(allocator, out, "{d}", .{if (parts.wday == 0) 7 else parts.wday}),
        'U' => try appendPadded(allocator, out, @divFloor(@as(i64, parts.yday) - 1 + 7 - parts.wday, 7), 2),
        'V' => try appendPadded(allocator, out, isoWeekYear(parts).week, 2),
        'w' => try runtime.appendFmt(allocator, out, "{d}", .{parts.wday}),
        'W' => try appendPadded(allocator, out, @divFloor(@as(i64, parts.yday) - 1 + 7 - @mod(@as(i64, parts.wday) + 6, 7), 7), 2),
        'y' => try appendPadded(allocator, out, @mod(parts.year, 100), 2),
        'Y' => try runtime.appendFmt(allocator, out, "{d}", .{parts.year}),
        'z' => {
            const magnitude: u32 = @abs(parts.offset);
            try out.append(allocator, if (parts.offset < 0) '-' else '+');
            try appendPadded(allocator, out, magnitude / 3600, 2);
            try appendPadded(allocator, out, magnitude / 60 % 60, 2);
        },
        'Z' => if (parts.zone) |zone| try out.appendSlice(allocator, zone) else if (parts.offset == 0) {
            try out.appendSlice(allocator, "UTC");
        } else {
            try appendConversion(state, out, 'z', parts);
        },
        else => unreachable,
    }
}

fn appendSequence(state: *State, out: *std.ArrayList(u8), comptime format: []const u8, parts: DateParts) anyerror!void {
    comptime var index: usize = 0;
    inline while (index < format.len) : (index += 1) {
        if (format[index] == '%') {
            index += 1;
            try appendConversion(state, out, format[index], parts);
        } else try out.append(state.allocator, format[index]);
    }
}

fn appendPadded(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: anytype, comptime width: usize) !void {
    const integer: i64 = @intCast(value);
    if (integer < 0) {
        try runtime.appendFmt(allocator, out, "-{d:0>" ++ std.fmt.comptimePrint("{d}", .{width - 1}) ++ "}", .{@abs(integer)});
    } else {
        try runtime.appendFmt(allocator, out, "{d:0>" ++ std.fmt.comptimePrint("{d}", .{width}) ++ "}", .{@as(u64, @intCast(integer))});
    }
}

fn isoWeekYear(parts: DateParts) struct { year: i64, week: i64 } {
    const iso_wday: i64 = if (parts.wday == 0) 7 else parts.wday;
    const week = @divFloor(@as(i64, parts.yday) - iso_wday + 10, 7);
    if (week < 1) return .{ .year = parts.year - 1, .week = isoWeeksInYear(parts.year - 1) };
    if (week > isoWeeksInYear(parts.year)) return .{ .year = parts.year + 1, .week = 1 };
    return .{ .year = parts.year, .week = week };
}

fn isoWeeksInYear(year: i64) i64 {
    const p = struct {
        fn f(y: i64) i64 {
            return @mod(y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400), 7);
        }
    }.f;
    return if (p(year) == 4 or p(year - 1) == 3) 53 else 52;
}

test "date fields follow strftime in the C locale" {
    const parts = brokenDownTime(0, .{ .name = "UTC" }).?;
    try std.testing.expectEqual(@as(i64, 1970), parts.year);
    try std.testing.expectEqual(@as(u8, 4), parts.wday);
    const before = brokenDownTime(-1, .{}).?;
    try std.testing.expectEqual(@as(i64, 1969), before.year);
    try std.testing.expectEqual(@as(u8, 23), before.hour);
    try std.testing.expectEqual(@as(u16, 365), before.yday);
    const iso = isoWeekYear(brokenDownTime(1609632000, .{}).?);
    try std.testing.expectEqual(@as(i64, 2020), iso.year);
    try std.testing.expectEqual(@as(i64, 53), iso.week);
    try std.testing.expect(brokenDownTime(std.math.maxInt(i64), .{}) == null);
}

test "os.date supports the C99 conversions in the C locale" {
    var state = try State.initWithOptions(std.testing.allocator, .{
        .stdlib = .{ .libraries = .{ .base = true, .string = true, .os = true } },
        .clock = .{ .fixed = 0 },
    });
    defer state.deinit();
    try state.executeSourceChunk(
        \\local fmt = "!%a %A %b %B %c %C %d %D %e %F %g %G %h %H %I %j %m %M %n %p %r %R %S %t %T %u %U %V %w %W %x %X %y %Y %z %%"
        \\assert(os.date(fmt, 1609632000) == "Sun Sunday Jan January Sun Jan  3 00:00:00 2021 20 03 01/03/21  3 2021-01-03 20 2020 Jan 00 12 003 01 00 \n AM 12:00:00 AM 00:00 00 \t 00:00:00 7 01 53 0 00 01/03/21 00:00:00 21 2021 +0000 %")
        \\assert(os.date(fmt, -31622400) == "Tue Tuesday Dec December Tue Dec 31 00:00:00 1968 19 31 12/31/68 31 1968-12-31 69 1969 Dec 00 12 366 12 00 \n AM 12:00:00 AM 00:00 00 \t 00:00:00 2 52 01 2 53 12/31/68 00:00:00 68 1968 +0000 %")
        \\assert(os.date("!%Ec|%EC|%Ex|%EX|%Ey|%EY|%Od|%Oe|%OH|%OI|%Om|%OM|%OS|%Ou|%OU|%OV|%Ow|%OW|%Oy", 1700000000) ==
        \\  "Tue Nov 14 22:13:20 2023|20|11/14/23|22:13:20|23|2023|14|14|22|10|11|13|20|2|46|46|2|46|23")
        \\assert(os.date("%Y-%m-%d") == "1970-01-01" and os.date() == "Thu Jan  1 00:00:00 1970")
        \\local ok, err = pcall(os.date, "%Ez")
        \\assert(not ok and err:find("invalid conversion specifier '%Ez'", 1, true))
    );
}

test "fixed local offsets shift os.date and os.time" {
    var state = try State.initWithOptions(std.testing.allocator, .{
        .stdlib = .{ .libraries = .{ .base = true, .os = true } },
        .clock = .{ .fixed_local = .{ .now = 0, .utc_offset = -5 * 3600 + -30 * 60, .is_dst = true, .cpu_seconds = 1.5 } },
    });
    defer state.deinit();
    try state.executeSourceChunk(
        \\assert(os.date("%Y-%m-%d %H:%M:%S %z", 0) == "1969-12-31 18:30:00 -0530")
        \\assert(os.date("!%Y-%m-%d %H:%M:%S %z", 0) == "1970-01-01 00:00:00 +0000")
        \\local t = os.date("*t", 0)
        \\assert(t.year == 1969 and t.hour == 18 and t.min == 30 and t.isdst == true)
        \\assert(os.time(t) == 0)
        \\assert(os.time({ year = 1970, month = 1, day = 1, hour = 0 }) == 5 * 3600 + 30 * 60)
        \\assert(os.clock() == 1.5)
        \\assert(os.date("%c", 86400 * 365 + 19800) == "Fri Jan  1 00:00:00 1971")
        \\assert(os.date("!%c", 86400 * 365) == "Fri Jan  1 00:00:00 1971")
        \\assert(os.date("!%Y", -86400 * 366) == "1968")
    );
}
