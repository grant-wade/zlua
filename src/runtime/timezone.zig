//! Local-time support for the clock capability: civil-date arithmetic,
//! POSIX TZ rules, and TZif zone files parsed with `std.tz`.

const std = @import("std");

pub const seconds_per_day: i64 = 86400;

/// Local-time offset for one instant, in seconds east of UTC.
pub const LocalOffset = struct {
    offset: i32 = 0,
    is_dst: bool = false,
    /// Zone abbreviation when known. Borrowed from the zone that produced it.
    name: ?[]const u8 = null,
};

pub const Civil = struct {
    year: i64,
    /// 1-12.
    month: u8,
    /// 1-31.
    day: u8,
};

/// Days since 1970-01-01 for a proleptic Gregorian date.
pub fn daysFromCivil(year: i64, month: i64, day: i64) i64 {
    const y = year - @intFromBool(month <= 2);
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const m = month + if (month > 2) @as(i64, -3) else @as(i64, 9);
    const doy = @divFloor(153 * m + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

pub fn civilFromDays(days: i64) Civil {
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const day = doy - @divFloor(153 * mp + 2, 5) + 1;
    const month = if (mp < 10) mp + 3 else mp - 9;
    return .{ .year = yoe + era * 400 + @intFromBool(month <= 2), .month = @intCast(month), .day = @intCast(day) };
}

pub fn isLeapYear(year: i64) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

/// Day of week for days since the epoch, with Sunday as 0.
pub fn weekday(days: i64) u8 {
    return @intCast(@mod(days + 4, 7));
}

/// A POSIX TZ rule such as `EST5EDT,M3.2.0,M11.1.0`.
pub const PosixRule = struct {
    std_name: Name,
    /// Standard offset in seconds east of UTC.
    std_offset: i32,
    dst: ?Dst = null,

    pub const Name = struct {
        bytes: [16]u8 = undefined,
        len: u8 = 0,

        fn slice(self: *const Name) []const u8 {
            return self.bytes[0..self.len];
        }
    };

    pub const Dst = struct {
        name: Name,
        offset: i32,
        start: Transition,
        end: Transition,
    };

    pub const Transition = struct {
        kind: enum { julian_no_leap, julian_zero, month_week_day },
        /// Julian day, or month for `month_week_day`.
        a: u16,
        /// Week (1-5) for `month_week_day`.
        b: u8 = 0,
        /// Weekday (0-6, Sunday = 0) for `month_week_day`.
        c: u8 = 0,
        /// Local time of day in seconds; may be negative or exceed one day.
        time: i32 = 2 * 3600,

        /// Seconds since the epoch at local midnight-based `time` in `year`.
        fn localSeconds(self: Transition, year: i64) i64 {
            const jan1 = daysFromCivil(year, 1, 1);
            const day: i64 = switch (self.kind) {
                .julian_no_leap => blk: {
                    var d: i64 = self.a - 1;
                    if (isLeapYear(year) and self.a >= 60) d += 1;
                    break :blk jan1 + d;
                },
                .julian_zero => jan1 + self.a,
                .month_week_day => blk: {
                    const first = daysFromCivil(year, self.a, 1);
                    var d = first + @mod(@as(i64, self.c) - weekday(first) + 7, 7) + (@as(i64, self.b) - 1) * 7;
                    const next_month = if (self.a == 12) daysFromCivil(year + 1, 1, 1) else daysFromCivil(year, self.a + 1, 1);
                    while (d >= next_month) d -= 7;
                    break :blk d;
                },
            };
            return day * seconds_per_day + self.time;
        }
    };

    pub fn parse(text: []const u8) ?PosixRule {
        var parser = Parser{ .text = text };
        return parser.rule();
    }

    pub fn offsetAt(self: *const PosixRule, timestamp: i64) LocalOffset {
        const standard: LocalOffset = .{ .offset = self.std_offset, .name = self.std_name.slice() };
        if (self.dst) |*dst| {
            const year = civilFromDays(@divFloor(timestamp + self.std_offset, seconds_per_day)).year;
            const start = dst.start.localSeconds(year) - self.std_offset;
            const end = dst.end.localSeconds(year) - dst.offset;
            const in_dst = if (start < end) timestamp >= start and timestamp < end else !(timestamp >= end and timestamp < start);
            if (in_dst) return .{ .offset = dst.offset, .is_dst = true, .name = dst.name.slice() };
        }
        return standard;
    }

    const Parser = struct {
        text: []const u8,
        index: usize = 0,

        fn rule(self: *Parser) ?PosixRule {
            const std_name = self.name() orelse return null;
            const std_offset = self.offset() orelse return null;
            var result = PosixRule{ .std_name = std_name, .std_offset = std_offset };
            if (self.index == self.text.len) return result;
            const dst_name = self.name() orelse return null;
            var dst_offset = std_offset + 3600;
            if (self.index < self.text.len and self.text[self.index] != ',') dst_offset = self.offset() orelse return null;
            var start = Transition{ .kind = .month_week_day, .a = 3, .b = 2, .c = 0 };
            var end = Transition{ .kind = .month_week_day, .a = 11, .b = 1, .c = 0 };
            if (self.index < self.text.len) {
                if (self.text[self.index] != ',') return null;
                self.index += 1;
                start = self.transition() orelse return null;
                if (self.index >= self.text.len or self.text[self.index] != ',') return null;
                self.index += 1;
                end = self.transition() orelse return null;
            }
            if (self.index != self.text.len) return null;
            result.dst = .{ .name = dst_name, .offset = dst_offset, .start = start, .end = end };
            return result;
        }

        fn name(self: *Parser) ?Name {
            var result = Name{};
            if (self.index < self.text.len and self.text[self.index] == '<') {
                self.index += 1;
                const start = self.index;
                while (self.index < self.text.len and self.text[self.index] != '>') self.index += 1;
                if (self.index >= self.text.len) return null;
                const bytes = self.text[start..self.index];
                self.index += 1;
                if (bytes.len < 3 or bytes.len > result.bytes.len) return null;
                @memcpy(result.bytes[0..bytes.len], bytes);
                result.len = @intCast(bytes.len);
                return result;
            }
            const start = self.index;
            while (self.index < self.text.len and std.ascii.isAlphabetic(self.text[self.index])) self.index += 1;
            const bytes = self.text[start..self.index];
            if (bytes.len < 3 or bytes.len > result.bytes.len) return null;
            @memcpy(result.bytes[0..bytes.len], bytes);
            result.len = @intCast(bytes.len);
            return result;
        }

        /// POSIX offsets are positive west of UTC; the result is east of UTC.
        fn offset(self: *Parser) ?i32 {
            const seconds = self.clockTime(24) orelse return null;
            return -seconds;
        }

        fn clockTime(self: *Parser, max_hours: i32) ?i32 {
            var sign: i32 = 1;
            if (self.index < self.text.len and (self.text[self.index] == '+' or self.text[self.index] == '-')) {
                if (self.text[self.index] == '-') sign = -1;
                self.index += 1;
            }
            const hours = self.number(0, max_hours) orelse return null;
            var seconds = hours * 3600;
            if (self.index < self.text.len and self.text[self.index] == ':') {
                self.index += 1;
                seconds += (self.number(0, 59) orelse return null) * 60;
                if (self.index < self.text.len and self.text[self.index] == ':') {
                    self.index += 1;
                    seconds += self.number(0, 59) orelse return null;
                }
            }
            return sign * seconds;
        }

        fn number(self: *Parser, min: i32, max: i32) ?i32 {
            const start = self.index;
            var value: i32 = 0;
            while (self.index < self.text.len and std.ascii.isDigit(self.text[self.index])) : (self.index += 1) {
                value = value * 10 + (self.text[self.index] - '0');
                if (value > max) return null;
            }
            if (self.index == start or value < min) return null;
            return value;
        }

        fn transition(self: *Parser) ?Transition {
            var result: Transition = undefined;
            if (self.index < self.text.len and self.text[self.index] == 'M') {
                self.index += 1;
                const month = self.number(1, 12) orelse return null;
                if (self.index >= self.text.len or self.text[self.index] != '.') return null;
                self.index += 1;
                const week = self.number(1, 5) orelse return null;
                if (self.index >= self.text.len or self.text[self.index] != '.') return null;
                self.index += 1;
                const day = self.number(0, 6) orelse return null;
                result = .{ .kind = .month_week_day, .a = @intCast(month), .b = @intCast(week), .c = @intCast(day) };
            } else if (self.index < self.text.len and self.text[self.index] == 'J') {
                self.index += 1;
                result = .{ .kind = .julian_no_leap, .a = @intCast(self.number(1, 365) orelse return null) };
            } else {
                result = .{ .kind = .julian_zero, .a = @intCast(self.number(0, 365) orelse return null) };
            }
            if (self.index < self.text.len and self.text[self.index] == '/') {
                self.index += 1;
                result.time = self.clockTime(167) orelse return null;
            }
            return result;
        }
    };
};

/// A loaded local time zone: TZif transitions with an optional POSIX footer,
/// or a POSIX rule alone.
pub const Zone = struct {
    allocator: std.mem.Allocator,
    transitions: []const Transition = &.{},
    types: []const Type = &.{},
    rule: ?PosixRule = null,

    pub const Transition = struct {
        at: i64,
        type_index: u8,
    };

    pub const Type = struct {
        offset: i32,
        is_dst: bool,
        name: [7]u8 = @splat(0),
        name_len: u8 = 0,
    };

    pub fn utc(allocator: std.mem.Allocator) Zone {
        return .{ .allocator = allocator, .rule = PosixRule.parse("UTC0").? };
    }

    pub fn fromRule(allocator: std.mem.Allocator, text: []const u8) ?Zone {
        return .{ .allocator = allocator, .rule = PosixRule.parse(text) orelse return null };
    }

    pub fn parseTzif(allocator: std.mem.Allocator, bytes: []const u8) !Zone {
        var reader: std.Io.Reader = .fixed(bytes);
        var tz = try std.tz.Tz.parse(allocator, &reader);
        defer tz.deinit();
        if (tz.timetypes.len > 256) return error.Malformed;

        const types = try allocator.alloc(Type, tz.timetypes.len);
        errdefer allocator.free(types);
        for (tz.timetypes, types) |*source, *target| {
            const name = source.name();
            target.* = .{ .offset = source.offset, .is_dst = source.isDst() };
            const len = @min(name.len, target.name.len);
            @memcpy(target.name[0..len], name[0..len]);
            target.name_len = @intCast(len);
        }
        const transitions = try allocator.alloc(Transition, tz.transitions.len);
        errdefer allocator.free(transitions);
        for (tz.transitions, transitions) |source, *target| {
            const index = (@intFromPtr(source.timetype) - @intFromPtr(tz.timetypes.ptr)) / @sizeOf(std.tz.Timetype);
            target.* = .{ .at = source.ts, .type_index = @intCast(index) };
        }
        return .{
            .allocator = allocator,
            .transitions = transitions,
            .types = types,
            .rule = if (tz.footer) |footer| PosixRule.parse(footer) else null,
        };
    }

    pub fn deinit(self: *Zone) void {
        self.allocator.free(self.transitions);
        self.allocator.free(self.types);
        self.* = undefined;
    }

    pub fn offsetAt(self: *const Zone, timestamp: i64) LocalOffset {
        if (self.types.len == 0) {
            if (self.rule) |*rule| return rule.offsetAt(timestamp);
            return .{};
        }
        if (self.transitions.len == 0 or timestamp < self.transitions[0].at) {
            if (self.transitions.len == 0) if (self.rule) |*rule| return rule.offsetAt(timestamp);
            return self.typeOffset(0);
        }
        const last = self.transitions[self.transitions.len - 1];
        if (timestamp >= last.at) {
            if (self.rule) |*rule| return rule.offsetAt(timestamp);
            return self.typeOffset(last.type_index);
        }
        var low: usize = 0;
        var high: usize = self.transitions.len;
        while (high - low > 1) {
            const middle = low + (high - low) / 2;
            if (self.transitions[middle].at <= timestamp) low = middle else high = middle;
        }
        return self.typeOffset(self.transitions[low].type_index);
    }

    fn typeOffset(self: *const Zone, index: usize) LocalOffset {
        const entry = &self.types[index];
        return .{ .offset = entry.offset, .is_dst = entry.is_dst, .name = entry.name[0..entry.name_len] };
    }
};

/// Converts local seconds (wall-clock seconds counted as if UTC) to a Unix
/// timestamp, following `mktime`: `is_dst` null lets the zone decide, while a
/// definite value prefers an offset with that daylight-saving state.
pub fn localToUtc(context: anytype, comptime offsetAt: fn (@TypeOf(context), i64) anyerror!LocalOffset, local: i64, is_dst: ?bool) !i64 {
    const first = try offsetAt(context, local);
    var guess = local - first.offset;
    var resolved = try offsetAt(context, guess);
    if (resolved.offset != first.offset) {
        const second = try offsetAt(context, local - resolved.offset);
        if (second.offset == resolved.offset) {
            guess = local - resolved.offset;
        } else {
            // The local time falls in a gap skipped by a forward transition:
            // read it with the earlier (smaller) offset, as C libraries do.
            const earlier = if (first.offset < resolved.offset) first else resolved;
            guess = local - earlier.offset;
            resolved = earlier;
        }
    }
    if (is_dst) |wanted| if (resolved.is_dst != wanted) {
        // Use an offset with the requested daylight-saving state: first across
        // a nearby transition, then from elsewhere in the year.
        var days: i64 = 1;
        while (days <= 366) : (days = if (days == 1) 30 else days + 30) {
            inline for (.{ -1, 1 }) |sign| {
                const probe = try offsetAt(context, guess + sign * days * seconds_per_day);
                if (probe.is_dst == wanted) return local - probe.offset;
            }
        }
    };
    return guess;
}

test "civil date round trips across eras" {
    inline for (.{ @as(i64, -719468), -1, 0, 1, 11016, 19723, 2932896, -2932897 }) |days| {
        const civil = civilFromDays(days);
        try std.testing.expectEqual(days, daysFromCivil(civil.year, civil.month, civil.day));
    }
    const epoch = civilFromDays(0);
    try std.testing.expectEqual(@as(i64, 1970), epoch.year);
    const before = civilFromDays(-1);
    try std.testing.expectEqual(@as(i64, 1969), before.year);
    try std.testing.expectEqual(@as(u8, 12), before.month);
    try std.testing.expectEqual(@as(u8, 31), before.day);
    try std.testing.expectEqual(@as(u8, 4), weekday(0));
    try std.testing.expectEqual(@as(u8, 3), weekday(-1));
}

test "posix rules resolve standard and daylight offsets" {
    const rule = PosixRule.parse("EST5EDT,M3.2.0,M11.1.0").?;
    // 2024-01-15T12:00:00Z is standard time.
    const winter = rule.offsetAt(1705320000);
    try std.testing.expectEqual(@as(i32, -5 * 3600), winter.offset);
    try std.testing.expect(!winter.is_dst);
    try std.testing.expectEqualStrings("EST", winter.name.?);
    // 2024-07-04T12:00:00Z is daylight time.
    const summer = rule.offsetAt(1720094400);
    try std.testing.expectEqual(@as(i32, -4 * 3600), summer.offset);
    try std.testing.expect(summer.is_dst);
    // DST starts 2024-03-10T07:00:00Z.
    try std.testing.expect(!rule.offsetAt(1710053999).is_dst);
    try std.testing.expect(rule.offsetAt(1710054000).is_dst);

    const south = PosixRule.parse("<+1030>-10:30<+11>-11,M10.1.0,M4.1.0").?;
    try std.testing.expectEqual(@as(i32, 11 * 3600), south.offsetAt(1705320000).offset);
    try std.testing.expectEqual(@as(i32, 10 * 3600 + 1800), south.offsetAt(1720094400).offset);

    const fixed = PosixRule.parse("JST-9").?;
    try std.testing.expectEqual(@as(i32, 9 * 3600), fixed.offsetAt(0).offset);
    try std.testing.expect(PosixRule.parse("UTC") == null);
    try std.testing.expect(PosixRule.parse("EST5EDT,M3") == null);
}

test "local times convert back to UTC like mktime" {
    const Context = struct {
        rule: PosixRule,
        fn offsetAt(self: *const @This(), timestamp: i64) anyerror!LocalOffset {
            return self.rule.offsetAt(timestamp);
        }
    };
    const context = Context{ .rule = PosixRule.parse("EST5EDT,M3.2.0,M11.1.0").? };
    // 2024-07-04 08:00:00 local daylight time.
    const local = daysFromCivil(2024, 7, 4) * seconds_per_day + 8 * 3600;
    try std.testing.expectEqual(@as(i64, 1720094400), try localToUtc(&context, Context.offsetAt, local, null));
    try std.testing.expectEqual(@as(i64, 1720094400), try localToUtc(&context, Context.offsetAt, local, true));
    try std.testing.expectEqual(@as(i64, 1720094400 + 3600), try localToUtc(&context, Context.offsetAt, local, false));
}

test "tzif zones use transitions and the footer rule" {
    // Minimal v2 TZif with one transition from LMT to EST and an EST5EDT footer.
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    const allocator = std.testing.allocator;
    const header = struct {
        fn write(list: *std.ArrayList(u8), timecnt: u32, typecnt: u32, charcnt: u32) !void {
            try list.appendSlice(std.testing.allocator, "TZif2");
            try list.appendNTimes(std.testing.allocator, 0, 15);
            inline for (.{ 0, 0, 0 }) |count| try appendInt(list, u32, count);
            try appendInt(list, u32, timecnt);
            try appendInt(list, u32, typecnt);
            try appendInt(list, u32, charcnt);
        }
        fn appendInt(list: *std.ArrayList(u8), comptime T: type, value: T) !void {
            var buffer: [@sizeOf(T)]u8 = undefined;
            std.mem.writeInt(T, &buffer, value, .big);
            try list.appendSlice(std.testing.allocator, &buffer);
        }
    };
    try header.write(&bytes, 0, 1, 4);
    try header.appendInt(&bytes, i32, 0);
    try bytes.appendSlice(allocator, &.{ 0, 0 });
    try bytes.appendSlice(allocator, "UTC\x00");
    try header.write(&bytes, 1, 2, 8);
    try header.appendInt(&bytes, i64, -2717650800);
    try bytes.append(allocator, 1);
    try header.appendInt(&bytes, i32, -17762);
    try bytes.appendSlice(allocator, &.{ 0, 0 });
    try header.appendInt(&bytes, i32, -18000);
    try bytes.appendSlice(allocator, &.{ 0, 4 });
    try bytes.appendSlice(allocator, "LMT\x00EST\x00");
    try bytes.appendSlice(allocator, "\nEST5EDT,M3.2.0,M11.1.0\n");

    var zone = try Zone.parseTzif(allocator, bytes.items);
    defer zone.deinit();
    try std.testing.expectEqual(@as(i32, -17762), zone.offsetAt(-3000000000).offset);
    try std.testing.expectEqualStrings("LMT", zone.offsetAt(-3000000000).name.?);
    try std.testing.expectEqual(@as(i32, -18000), zone.offsetAt(1705320000).offset);
    try std.testing.expectEqual(@as(i32, -14400), zone.offsetAt(1720094400).offset);
    try std.testing.expectEqualStrings("EDT", zone.offsetAt(1720094400).name.?);
}
