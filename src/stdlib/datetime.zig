const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const metatable_mod = @import("../runtime/metatable.zig");
const timezone = @import("../runtime/timezone.zig");
const system_mod = @import("../runtime/system.zig");
const os = @import("os.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Table = runtime.Table;

const ns_per_s: i128 = std.time.ns_per_s;
/// Largest year magnitude a datetime may have.
pub const max_year = 1_000_000_000;
/// Largest Unix-seconds magnitude accepted, about `max_year` years.
pub const max_unix_seconds: i64 = 31_556_952 * max_year;
const ns_per_day: i128 = ns_per_s * timezone.seconds_per_day;

/// A TOML date-time: an offset date-time, local date-time, local date, or local time.
pub const DateTime = struct {
    date: ?Date = null,
    time: ?Time = null,
    /// Minutes east of UTC. Only date-times with both a date and a time have one.
    offset: ?i16 = null,

    pub const Kind = enum {
        datetime,
        local_datetime,
        date,
        time,

        pub fn name(self: Kind) []const u8 {
            return switch (self) {
                .datetime => "datetime",
                .local_datetime => "local datetime",
                .date => "date",
                .time => "time",
            };
        }
    };

    pub fn kind(self: DateTime) Kind {
        if (self.offset != null) return .datetime;
        if (self.date != null and self.time != null) return .local_datetime;
        if (self.date != null) return .date;
        return .time;
    }

    pub fn format(self: DateTime, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.date) |date| {
            if (date.year >= 0 and date.year <= 9999) {
                try writer.print("{d:0>4}", .{@as(u64, @intCast(date.year))});
            } else {
                try writer.print("{d}", .{date.year});
            }
            try writer.print("-{d:0>2}-{d:0>2}", .{ date.month, date.day });
            if (self.time != null) try writer.writeByte('T');
        }
        if (self.time) |time| {
            try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ time.hour, time.minute, time.second });
            if (time.nanosecond != 0) {
                var digits: [9]u8 = undefined;
                _ = std.fmt.bufPrint(&digits, "{d:0>9}", .{time.nanosecond}) catch unreachable;
                try writer.print(".{s}", .{std.mem.trimEnd(u8, &digits, "0")});
            }
        }
        if (self.offset) |offset| {
            if (offset == 0) return writer.writeByte('Z');
            const magnitude = @abs(offset);
            try writer.print("{c}{d:0>2}:{d:0>2}", .{ @as(u8, if (offset < 0) '-' else '+'), magnitude / 60, magnitude % 60 });
        }
    }

    /// Seconds since 1970-01-01T00:00 on the wall clock, ignoring the offset. A missing date
    /// counts as that day and a missing time as midnight.
    fn localSeconds(self: DateTime) i64 {
        var seconds: i64 = 0;
        if (self.date) |date| seconds = timezone.daysFromCivil(date.year, date.month, date.day) * timezone.seconds_per_day;
        if (self.time) |time| seconds += @as(i64, time.hour) * 3600 + @as(i64, time.minute) * 60 + time.second;
        return seconds;
    }

    fn nanosecond(self: DateTime) u32 {
        return if (self.time) |time| time.nanosecond else 0;
    }

    /// Seconds since the Unix epoch. The date-time must have an offset.
    pub fn unixSeconds(self: DateTime) i64 {
        return self.localSeconds() - @as(i64, self.offset.?) * 60;
    }

    /// Nanoseconds used to order and subtract values of the same kind.
    fn orderKey(self: DateTime) i128 {
        const seconds = if (self.offset != null) self.unixSeconds() else self.localSeconds();
        return @as(i128, seconds) * ns_per_s + self.nanosecond();
    }

    pub fn fromUnix(seconds: i64, nano: u32) DateTime {
        return fromLocal(.datetime, @as(i128, seconds) * ns_per_s + nano, 0) catch unreachable;
    }

    /// Builds a value of `target` from nanoseconds since 1970-01-01T00:00 on the wall clock.
    fn fromLocal(target: Kind, nanoseconds: i128, offset: ?i16) error{Overflow}!DateTime {
        const total_seconds = std.math.cast(i64, @divFloor(nanoseconds, ns_per_s)) orelse return error.Overflow;
        const nano: u32 = @intCast(@mod(nanoseconds, ns_per_s));
        const days = @divFloor(total_seconds, timezone.seconds_per_day);
        const rest: u32 = @intCast(@mod(total_seconds, timezone.seconds_per_day));
        var result: DateTime = .{ .offset = if (target == .datetime) offset else null };
        if (target != .time) {
            const civil = timezone.civilFromDays(days);
            result.date = .{ .year = civil.year, .month = civil.month, .day = civil.day };
        }
        if (target != .date) {
            result.time = .{ .hour = @intCast(rest / 3600), .minute = @intCast(rest / 60 % 60), .second = @intCast(rest % 60), .nanosecond = nano };
        }
        return result;
    }

    fn atOffset(self: DateTime, minutes: i16) DateTime {
        const instant = @as(i128, self.unixSeconds()) * ns_per_s + self.nanosecond();
        return fromLocal(.datetime, instant + @as(i128, minutes) * 60 * ns_per_s, minutes) catch unreachable;
    }
};

pub const Date = struct {
    year: i64,
    month: u8,
    day: u8,
};

pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32 = 0,
};

/// Where and why `scan` stopped.
pub const Failure = struct {
    offset: usize,
    message: []const u8,
};

/// Scans a TOML date-time starting at `start`, which must hold a digit. Returns the value
/// and the offset just past it.
pub fn scan(input: []const u8, start: usize, failure: *Failure) error{Invalid}!struct { DateTime, usize } {
    var scanner: Scanner = .{ .input = input, .pos = start, .start = start, .failure = failure };
    var result: DateTime = .{};
    if (input.len - start >= 3 and input[start + 2] == ':') {
        result.time = try scanner.time();
        return .{ result, scanner.pos };
    }
    result.date = try scanner.date();
    const has_time = if (scanner.peek()) |byte|
        byte == 'T' or byte == 't' or (byte == ' ' and input.len - scanner.pos >= 4 and std.ascii.isDigit(input[scanner.pos + 1]) and std.ascii.isDigit(input[scanner.pos + 2]) and input[scanner.pos + 3] == ':')
    else
        false;
    if (!has_time) return .{ result, scanner.pos };
    scanner.pos += 1;
    result.time = try scanner.time();
    if (scanner.peek()) |byte| switch (byte) {
        'Z', 'z' => {
            scanner.pos += 1;
            result.offset = 0;
        },
        '+', '-' => {
            scanner.pos += 1;
            const hour = try scanner.digits(2);
            try scanner.expect(':');
            const minute = try scanner.digits(2);
            if (hour > 23 or minute > 59) return scanner.fail("invalid time offset");
            const magnitude: i16 = @intCast(hour * 60 + minute);
            result.offset = if (byte == '-') -magnitude else magnitude;
        },
        else => {},
    };
    return .{ result, scanner.pos };
}

pub fn parse(text: []const u8, failure: *Failure) error{Invalid}!DateTime {
    if (text.len == 0 or !std.ascii.isDigit(text[0])) {
        failure.* = .{ .offset = 0, .message = "invalid date or time" };
        return error.Invalid;
    }
    const value, const end = try scan(text, 0, failure);
    if (end != text.len) {
        failure.* = .{ .offset = end, .message = "unexpected text after the date or time" };
        return error.Invalid;
    }
    return value;
}

const Scanner = struct {
    input: []const u8,
    pos: usize,
    start: usize,
    failure: *Failure,

    fn fail(self: *Scanner, message: []const u8) error{Invalid} {
        self.failure.* = .{ .offset = self.start, .message = message };
        return error.Invalid;
    }

    fn peek(self: *const Scanner) ?u8 {
        return if (self.pos < self.input.len) self.input[self.pos] else null;
    }

    fn date(self: *Scanner) !Date {
        const year = try self.digits(4);
        try self.expect('-');
        const month = try self.digits(2);
        try self.expect('-');
        const day = try self.digits(2);
        if (month < 1 or month > 12 or day < 1 or day > daysInMonth(year, @intCast(month))) return self.fail("invalid date");
        return .{ .year = year, .month = @intCast(month), .day = @intCast(day) };
    }

    fn time(self: *Scanner) !Time {
        const hour = try self.digits(2);
        try self.expect(':');
        const minute = try self.digits(2);
        var result: Time = .{ .hour = @intCast(hour), .minute = @intCast(minute), .second = 0 };
        if (self.peek() == ':') {
            self.pos += 1;
            result.second = @intCast(try self.digits(2));
            if (self.peek() == '.') {
                self.pos += 1;
                const digits_start = self.pos;
                while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) : (self.pos += 1) {
                    if (self.pos - digits_start < 9) result.nanosecond = result.nanosecond * 10 + (self.input[self.pos] - '0');
                }
                const count = self.pos - digits_start;
                if (count == 0) return self.fail("expected digits after the decimal point in the time");
                for (count..9) |_| result.nanosecond *= 10;
            }
        }
        if (result.hour > 23 or result.minute > 59 or result.second > 60) return self.fail("invalid time");
        return result;
    }

    fn digits(self: *Scanner, count: usize) !u16 {
        if (self.input.len - self.pos < count) return self.fail("invalid date or time");
        var result: u16 = 0;
        for (self.input[self.pos..][0..count]) |byte| {
            if (!std.ascii.isDigit(byte)) return self.fail("invalid date or time");
            result = result * 10 + (byte - '0');
        }
        self.pos += count;
        return result;
    }

    fn expect(self: *Scanner, byte: u8) !void {
        if (self.peek() != byte) return self.fail("invalid date or time");
        self.pos += 1;
    }
};

pub fn daysInMonth(year: i64, month: u8) u8 {
    return switch (month) {
        2 => if (timezone.isLeapYear(year)) 29 else 28,
        4, 6, 9, 11 => 30,
        else => 31,
    };
}

const method_fields = .{
    .{ "kind", runtime.NativeFn.datetime_kind },
    .{ "unix", runtime.NativeFn.datetime_unix_method },
    .{ "utc", runtime.NativeFn.datetime_utc },
    .{ "at_offset", runtime.NativeFn.datetime_at_offset },
    .{ "with", runtime.NativeFn.datetime_with },
    .{ "add", runtime.NativeFn.datetime_add },
    .{ "date", runtime.NativeFn.datetime_date },
    .{ "time", runtime.NativeFn.datetime_time },
    .{ "weekday", runtime.NativeFn.datetime_weekday },
    .{ "yday", runtime.NativeFn.datetime_yday },
    .{ "format", runtime.NativeFn.datetime_format },
};

fn metatable(state: *State) !*Table {
    const tables = &state.library_tables;
    if (tables.get(.data_datetime_metatable)) |existing| return existing;
    const methods = (try state.newTableWithHints(0, method_fields.len)).table;
    inline for (method_fields) |method| try setNamed(state, methods, method[0], .{ .native = method[1] });
    const created = (try state.newTableWithHints(0, 8)).table;
    try setNamed(state, created, "__metatable", .{ .boolean = false });
    try setNamed(state, created, "__name", .{ .string = try state.strings.intern("datetime") });
    try setNamed(state, created, "__index", .{ .table = methods });
    try setNamed(state, created, "__tostring", .{ .native = .datetime_tostring });
    try setNamed(state, created, "__eq", .{ .native = .datetime_eq });
    try setNamed(state, created, "__lt", .{ .native = .datetime_lt });
    try setNamed(state, created, "__le", .{ .native = .datetime_le });
    try setNamed(state, created, "__sub", .{ .native = .datetime_sub });
    tables.set(.data_datetime_metatable, created);
    return created;
}

fn setNamed(state: *State, table: *Table, name: []const u8, value: Value) !void {
    try state.setTableRaw(table, .{ .string = try state.strings.intern(name) }, value);
}

pub fn isDateTime(state: *State, table: *Table) bool {
    const expected = state.library_tables.get(.data_datetime_metatable) orelse return false;
    return table.metatable == expected;
}

pub fn toLua(state: *State, value: DateTime) !Value {
    const mt = try metatable(state);
    const table = (try state.newTableWithHints(0, 8)).table;
    try metatable_mod.setTableMetatableRaw(state, table, mt);
    if (value.date) |date| {
        try setField(state, table, "year", date.year);
        try setField(state, table, "month", date.month);
        try setField(state, table, "day", date.day);
    }
    if (value.time) |time| {
        try setField(state, table, "hour", time.hour);
        try setField(state, table, "min", time.minute);
        try setField(state, table, "sec", time.second);
        try setField(state, table, "nsec", time.nanosecond);
    }
    if (value.offset) |offset| try setField(state, table, "offset", offset);
    return .{ .table = table };
}

fn setField(state: *State, table: *Table, comptime name: []const u8, value: i64) !void {
    try setNamed(state, table, name, .{ .integer = value });
}

/// Reads the date-time fields of `table`, or returns the reason they are invalid.
pub fn fromTable(table: *Table) union(enum) { ok: DateTime, invalid: []const u8 } {
    var result: DateTime = .{};
    const year = field(table, "year");
    const month = field(table, "month");
    const day = field(table, "day");
    if (year != .absent or month != .absent or day != .absent) {
        const y = year.integer() orelse return .{ .invalid = "year must be an integer" };
        const m = month.integer() orelse return .{ .invalid = "month must be an integer" };
        const d = day.integer() orelse return .{ .invalid = "day must be an integer" };
        if (y < -max_year or y > max_year) return .{ .invalid = "year is out of range" };
        if (m < 1 or m > 12) return .{ .invalid = "month must be between 1 and 12" };
        if (d < 1 or d > daysInMonth(y, @intCast(m))) return .{ .invalid = "day is out of range for the month" };
        result.date = .{ .year = y, .month = @intCast(m), .day = @intCast(d) };
    }
    const hour = field(table, "hour");
    const minute = field(table, "min");
    const second = field(table, "sec");
    const nanosecond = field(table, "nsec");
    if (hour != .absent or minute != .absent or second != .absent or nanosecond != .absent) {
        const h = hour.integer() orelse return .{ .invalid = "hour must be an integer" };
        const m = minute.integerOr(0) orelse return .{ .invalid = "min must be an integer" };
        const s = second.integerOr(0) orelse return .{ .invalid = "sec must be an integer" };
        const n = nanosecond.integerOr(0) orelse return .{ .invalid = "nsec must be an integer" };
        if (h < 0 or h > 23) return .{ .invalid = "hour must be between 0 and 23" };
        if (m < 0 or m > 59) return .{ .invalid = "min must be between 0 and 59" };
        if (s < 0 or s > 60) return .{ .invalid = "sec must be between 0 and 60" };
        if (n < 0 or n > 999_999_999) return .{ .invalid = "nsec must be between 0 and 999999999" };
        result.time = .{ .hour = @intCast(h), .minute = @intCast(m), .second = @intCast(s), .nanosecond = @intCast(n) };
    }
    const offset = field(table, "offset");
    if (offset != .absent) {
        const o = offset.integer() orelse return .{ .invalid = "offset must be an integer" };
        if (o <= -24 * 60 or o >= 24 * 60) return .{ .invalid = "offset must be less than 24 hours" };
        if (result.date == null or result.time == null) return .{ .invalid = "only a date with a time can have an offset" };
        result.offset = @intCast(o);
    }
    if (result.date == null and result.time == null) return .{ .invalid = "needs a date, a time, or both" };
    return .{ .ok = result };
}

const Field = union(enum) {
    absent,
    present: Value,

    fn integer(self: Field) ?i64 {
        return switch (self) {
            .absent => null,
            .present => |value| runtime.toInteger(value),
        };
    }

    fn integerOr(self: Field, default: i64) ?i64 {
        return if (self == .absent) default else self.integer();
    }
};

fn field(table: *Table, comptime name: []const u8) Field {
    const value = table.getLiteral(name);
    return if (value == .nil) .absent else .{ .present = value };
}

fn returnValue(state: *State, thread: *Thread, op: bytecode.Call, value: Value) !void {
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}

fn returnDateTime(state: *State, thread: *Thread, op: bytecode.Call, value: DateTime) !void {
    try returnValue(state, thread, op, try toLua(state, value));
}

fn returnText(state: *State, thread: *Thread, op: bytecode.Call, value: DateTime) !void {
    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{f}", .{value}) catch unreachable;
    try returnValue(state, thread, op, .{ .string = try state.strings.intern(text) });
}

fn expectDateTime(state: *State, thread: *Thread, op: bytecode.Call, comptime name: []const u8, index: u32) !DateTime {
    const value = runtime.argValue(state, thread, op, index);
    if (value != .table or !isDateTime(state, value.table)) return state.failArgumentType(name, index + 1, "datetime", value);
    return switch (fromTable(value.table)) {
        .ok => |parsed| parsed,
        .invalid => |message| state.failArgumentMessage(name, index + 1, message),
    };
}

fn failMissing(state: *State, comptime name: []const u8, value: DateTime, comptime what: []const u8) runtime.RuntimeError {
    var buffer: [96]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "a {s} has no " ++ what, .{value.kind().name()}) catch unreachable;
    return state.failArgumentMessage(name, 1, message);
}

pub fn parseText(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime.parse";
    const text = try state.expectArgumentString(thread, op, name, 0);
    var failure: Failure = undefined;
    const value = parse(text, &failure) catch {
        var buffer: [128]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "{s} at character {d}", .{ failure.message, failure.offset + 1 }) catch failure.message;
        return state.failArgumentMessage(name, 1, message);
    };
    try returnDateTime(state, thread, op, value);
}

pub fn new(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime.new";
    const arg = runtime.argValue(state, thread, op, 0);
    if (arg != .table) return state.failArgumentType(name, 1, "table", arg);
    switch (fromTable(arg.table)) {
        .ok => |value| try returnDateTime(state, thread, op, value),
        .invalid => |message| return state.failArgumentMessage(name, 1, message),
    }
}

pub fn unix(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime.unix";
    const arg = runtime.argValue(state, thread, op, 0);
    var seconds: i64 = undefined;
    var nano: i64 = 0;
    switch (arg) {
        .integer => |integer| seconds = integer,
        .number => |number| {
            if (!std.math.isFinite(number) or @abs(number) > 9.2e18) return state.failArgumentMessage(name, 1, "number out of range");
            const whole = @floor(number);
            seconds = @intFromFloat(whole);
            nano = @intFromFloat(@min((number - whole) * 1e9, 999_999_999));
        },
        else => return state.failArgumentType(name, 1, "number", arg),
    }
    if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil) {
        const nsec_arg = runtime.argValue(state, thread, op, 1);
        nano = runtime.toInteger(nsec_arg) orelse return state.failArgumentType(name, 2, "integer", nsec_arg);
        if (nano < 0 or nano > 999_999_999) return state.failArgumentMessage(name, 2, "nanoseconds must be between 0 and 999999999");
    }
    if (@abs(seconds) > max_unix_seconds) return state.failArgumentMessage(name, 1, "number out of range");
    try returnDateTime(state, thread, op, DateTime.fromUnix(seconds, @intCast(nano)));
}

/// `datetime.now([offset | "local"])`.
pub fn now(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime.now";
    const seconds = try system_mod.currentTime(state);
    const current = DateTime.fromUnix(seconds, 0);
    if (op.arg_count == 0 or runtime.argValue(state, thread, op, 0) == .nil) return returnDateTime(state, thread, op, current);
    const arg = runtime.argValue(state, thread, op, 0);
    const minutes: i64 = switch (arg) {
        .string => |string| if (std.mem.eql(u8, string.bytes(), "local"))
            @divTrunc((try system_mod.localOffset(state, seconds)).offset, 60)
        else
            return state.failArgumentMessage(name, 1, "expected an offset in minutes or 'local'"),
        else => runtime.toInteger(arg) orelse return state.failArgumentType(name, 1, "integer or 'local'", arg),
    };
    if (minutes <= -24 * 60 or minutes >= 24 * 60) return state.failArgumentMessage(name, 1, "offset must be less than 24 hours");
    try returnDateTime(state, thread, op, current.atOffset(@intCast(minutes)));
}

pub fn tostring(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try returnText(state, thread, op, try expectDateTime(state, thread, op, "datetime.__tostring", 0));
}

fn valueOf(state: *State, value: Value) ?DateTime {
    if (value != .table or !isDateTime(state, value.table)) return null;
    return switch (fromTable(value.table)) {
        .ok => |parsed| parsed,
        .invalid => null,
    };
}

fn operands(state: *State, thread: *Thread, op: bytecode.Call, comptime verb: []const u8) !struct { DateTime, DateTime } {
    const left = runtime.argValue(state, thread, op, 0);
    const right = runtime.argValue(state, thread, op, 1);
    const left_value = valueOf(state, left);
    const right_value = valueOf(state, right);
    if (left_value == null or right_value == null) {
        return failOperands(state, verb, metatable_mod.luaTypeNameForError(state, left), metatable_mod.luaTypeNameForError(state, right));
    }
    if (left_value.?.kind() != right_value.?.kind()) return failOperands(state, verb, left_value.?.kind().name(), right_value.?.kind().name());
    return .{ left_value.?, right_value.? };
}

fn failOperands(state: *State, comptime verb: []const u8, left: []const u8, right: []const u8) runtime.RuntimeError {
    var buffer: [96]u8 = undefined;
    const message = if (comptime std.mem.eql(u8, verb, "subtract"))
        std.fmt.bufPrint(&buffer, "attempt to subtract a {s} from a {s}", .{ right, left }) catch unreachable
    else
        std.fmt.bufPrint(&buffer, "attempt to " ++ verb ++ " a {s} with a {s}", .{ left, right }) catch unreachable;
    return state.fail(message);
}

pub fn eq(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const left = valueOf(state, runtime.argValue(state, thread, op, 0));
    const right = valueOf(state, runtime.argValue(state, thread, op, 1));
    const equal = left != null and right != null and left.?.kind() == right.?.kind() and left.?.orderKey() == right.?.orderKey();
    try returnValue(state, thread, op, .{ .boolean = equal });
}

pub fn lt(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const left, const right = try operands(state, thread, op, "compare");
    try returnValue(state, thread, op, .{ .boolean = left.orderKey() < right.orderKey() });
}

pub fn le(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const left, const right = try operands(state, thread, op, "compare");
    try returnValue(state, thread, op, .{ .boolean = left.orderKey() <= right.orderKey() });
}

pub fn sub(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const left, const right = try operands(state, thread, op, "subtract");
    const difference = left.orderKey() - right.orderKey();
    const seconds: f64 = @floatFromInt(@divFloor(difference, ns_per_s));
    const fraction: f64 = @floatFromInt(@mod(difference, ns_per_s));
    try returnValue(state, thread, op, .{ .number = seconds + fraction / 1e9 });
}

pub fn kindMethod(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = try expectDateTime(state, thread, op, "datetime:kind", 0);
    try returnValue(state, thread, op, .{ .string = try state.strings.intern(value.kind().name()) });
}

pub fn unixMethod(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:unix";
    const value = try expectDateTime(state, thread, op, name, 0);
    if (value.offset == null) return failMissing(state, name, value, "offset");
    try state.returnValues(thread, op.base, op.return_count, &.{ .{ .integer = value.unixSeconds() }, .{ .integer = value.nanosecond() } });
}

pub fn utc(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:utc";
    const value = try expectDateTime(state, thread, op, name, 0);
    if (value.offset == null) return failMissing(state, name, value, "offset");
    try returnDateTime(state, thread, op, value.atOffset(0));
}

pub fn atOffset(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:at_offset";
    const value = try expectDateTime(state, thread, op, name, 0);
    if (value.offset == null) return failMissing(state, name, value, "offset");
    const arg = runtime.argValue(state, thread, op, 1);
    const minutes = runtime.toInteger(arg) orelse return state.failArgumentType(name, 2, "integer", arg);
    if (minutes <= -24 * 60 or minutes >= 24 * 60) return state.failArgumentMessage(name, 2, "offset must be less than 24 hours");
    try returnDateTime(state, thread, op, value.atOffset(@intCast(minutes)));
}

const field_names = [_][]const u8{ "year", "month", "day", "hour", "min", "sec", "nsec", "offset" };

pub fn with(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:with";
    _ = try expectDateTime(state, thread, op, name, 0);
    const source = runtime.argValue(state, thread, op, 0).table;
    const changes = runtime.argValue(state, thread, op, 1);
    if (changes != .table) return state.failArgumentType(name, 2, "table", changes);
    const merged = (try state.newTableWithHints(0, field_names.len)).table;
    for (field_names) |key| {
        const changed = changes.table.getBytes(key);
        const value = if (changed != .nil) changed else source.getBytes(key);
        if (value != .nil) try setNamed(state, merged, key, value);
    }
    switch (fromTable(merged)) {
        .ok => |value| try returnDateTime(state, thread, op, value),
        .invalid => |message| return state.failArgumentMessage(name, 2, message),
    }
}

const add_units = [_]struct { []const u8, i128 }{
    .{ "weeks", 7 * ns_per_day },
    .{ "days", ns_per_day },
    .{ "hours", 3600 * ns_per_s },
    .{ "minutes", 60 * ns_per_s },
    .{ "seconds", ns_per_s },
    .{ "nanoseconds", 1 },
};

pub fn add(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:add";
    var value = try expectDateTime(state, thread, op, name, 0);
    const arg = runtime.argValue(state, thread, op, 1);
    if (arg != .table) return state.failArgumentType(name, 2, "table", arg);

    var months: i128 = 0;
    var span: i128 = 0;
    for (arg.table.array.items()) |item| {
        if (item != .nil) return state.failArgumentMessage(name, 2, "expected named amounts such as days or hours");
    }
    for (arg.table.entries()) |entry| {
        if (entry.value == .nil) continue;
        if (entry.key != .string) return state.failArgumentMessage(name, 2, "expected named amounts such as days or hours");
        const key = entry.key.string.bytes();
        const amount = runtime.toInteger(entry.value) orelse return failAmount(state, name, key, "must be an integer");
        if (std.mem.eql(u8, key, "years")) {
            months += @as(i128, amount) * 12;
        } else if (std.mem.eql(u8, key, "months")) {
            months += amount;
        } else for (add_units) |unit| {
            if (std.mem.eql(u8, key, unit[0])) {
                span += @as(i128, amount) * unit[1];
                break;
            }
        } else return failAmount(state, name, key, "is not a known amount");
    }

    if (months != 0) {
        const date = value.date orelse return failMissing(state, name, value, "date to add months or years to");
        const total = @as(i128, date.year) * 12 + (date.month - 1) + months;
        const year = std.math.cast(i64, @divFloor(total, 12)) orelse return state.failArgumentMessage(name, 2, "result is out of range");
        if (@abs(year) > max_year) return state.failArgumentMessage(name, 2, "result is out of range");
        const month: u8 = @intCast(@mod(total, 12) + 1);
        value.date = .{ .year = year, .month = month, .day = @min(date.day, daysInMonth(year, month)) };
    }
    if (value.kind() == .date and @mod(span, ns_per_day) != 0) return state.failArgumentMessage(name, 2, "a date can only add whole days");

    var total = @as(i128, value.localSeconds()) * ns_per_s + value.nanosecond() + span;
    if (value.kind() == .time) total = @mod(total, ns_per_day);
    if (@abs(@divFloor(total, ns_per_s)) > max_unix_seconds) return state.failArgumentMessage(name, 2, "result is out of range");
    const result = DateTime.fromLocal(value.kind(), total, value.offset) catch return state.failArgumentMessage(name, 2, "result is out of range");
    try returnDateTime(state, thread, op, result);
}

fn failAmount(state: *State, comptime name: []const u8, key: []const u8, comptime problem: []const u8) runtime.RuntimeError {
    var buffer: [96]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "'{s}' " ++ problem, .{key[0..@min(key.len, 32)]}) catch unreachable;
    return state.failArgumentMessage(name, 2, message);
}

pub fn dateMethod(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:date";
    const value = try expectDateTime(state, thread, op, name, 0);
    if (value.date == null) return failMissing(state, name, value, "date");
    try returnDateTime(state, thread, op, .{ .date = value.date });
}

pub fn timeMethod(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:time";
    const value = try expectDateTime(state, thread, op, name, 0);
    if (value.time == null) return failMissing(state, name, value, "time");
    try returnDateTime(state, thread, op, .{ .time = value.time });
}

pub fn weekday(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:weekday";
    const value = try expectDateTime(state, thread, op, name, 0);
    const date = value.date orelse return failMissing(state, name, value, "date");
    const sunday_based = timezone.weekday(timezone.daysFromCivil(date.year, date.month, date.day));
    try returnValue(state, thread, op, .{ .integer = if (sunday_based == 0) 7 else sunday_based });
}

pub fn yday(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:yday";
    const value = try expectDateTime(state, thread, op, name, 0);
    const date = value.date orelse return failMissing(state, name, value, "date");
    try returnValue(state, thread, op, .{ .integer = dayOfYear(date) });
}

fn dayOfYear(date: Date) i64 {
    return timezone.daysFromCivil(date.year, date.month, date.day) - timezone.daysFromCivil(date.year, 1, 1) + 1;
}

const date_conversions = "aAbBCdDeFgGhjmuUVwWxyY";
const time_conversions = "HIMprRSTXf";

pub fn formatMethod(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "datetime:format";
    const value = try expectDateTime(state, thread, op, name, 0);
    if (op.arg_count < 2 or runtime.argValue(state, thread, op, 1) == .nil) return returnText(state, thread, op, value);
    const pattern = try state.expectArgumentString(thread, op, name, 1);

    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        if (pattern[index] != '%' or index + 1 == pattern.len) continue;
        index += 1;
        var conversion = pattern[index];
        if ((conversion == 'E' or conversion == 'O') and index + 1 < pattern.len) {
            index += 1;
            conversion = pattern[index];
        }
        if (conversion == 'c') {
            if (value.date == null or value.time == null) return failMissing(state, name, value, "date and time for '%c'");
        } else if (std.mem.indexOfScalar(u8, date_conversions, conversion) != null) {
            if (value.date == null) return failMissing(state, name, value, "date");
        } else if (std.mem.indexOfScalar(u8, time_conversions, conversion) != null) {
            if (value.time == null) return failMissing(state, name, value, "time");
        } else if (conversion == 'z' or conversion == 'Z') {
            if (value.offset == null) return failMissing(state, name, value, "offset");
        }
    }

    const date = value.date orelse Date{ .year = 1970, .month = 1, .day = 1 };
    const time = value.time orelse Time{ .hour = 0, .minute = 0, .second = 0 };
    const parts: os.DateParts = .{
        .year = date.year,
        .month = date.month,
        .day = date.day,
        .hour = time.hour,
        .min = time.minute,
        .sec = time.second,
        .yday = @intCast(dayOfYear(date)),
        .wday = timezone.weekday(timezone.daysFromCivil(date.year, date.month, date.day)),
        .is_dst = false,
        .offset = @as(i32, value.offset orelse 0) * 60,
        .zone = if (value.offset == 0) "UTC" else null,
    };
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(state.allocator);
    try os.formatDate(state, &out, pattern, parts, name, time.nanosecond);
    try returnValue(state, thread, op, .{ .string = try state.strings.intern(out.items) });
}

test "datetime.now reads the state's clock and exists only with os" {
    const entry_mod = @import("../runtime/entry.zig");
    var state = try State.initWithOptions(std.testing.allocator, .{
        .stdlib = .{ .libraries = .{ .base = true, .os = true, .datetime = true } },
        .clock = .{ .fixed_local = .{ .now = 1700000000, .utc_offset = -5 * 3600 - 30 * 60, .cpu_seconds = 0 } },
    });
    defer state.deinit();
    try entry_mod.executeSourceChunk(&state,
        \\assert(tostring(datetime.now()) == "2023-11-14T22:13:20Z")
        \\assert(tostring(datetime.now(60)) == "2023-11-14T23:13:20+01:00")
        \\assert(tostring(datetime.now("local")) == "2023-11-14T16:43:20-05:30")
        \\assert(datetime.now("local") == datetime.now())
        \\assert(not pcall(datetime.now, "elsewhere"))
    );

    var safe = try State.initWithOptions(std.testing.allocator, .{
        .stdlib = .{ .libraries = .{ .base = true, .datetime = true } },
        .clock = .{ .fixed = 0 },
    });
    defer safe.deinit();
    try entry_mod.executeSourceChunk(&safe,
        \\assert(datetime.now == nil and tostring(datetime.unix(0)) == "1970-01-01T00:00:00Z")
    );
}
