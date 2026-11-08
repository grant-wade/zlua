const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const data = @import("data.zig");
const datetime = @import("datetime.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Table = runtime.Table;

pub fn nullValue(state: *State) !Value {
    return data.nullValue(state);
}

pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const input = try data.inputBytes(state, runtime.argValue(state, thread, op, 0), "msgpack.read");
    var reader: Reader = .{ .state = state, .input = input, .builder = .init(state) };
    defer reader.builder.deinit();
    try data.returnValue(state, thread, op, try reader.document());
}

const Reader = struct {
    state: *State,
    input: []const u8,
    pos: usize = 0,
    builder: data.Builder,

    fn fail(self: *Reader, offset: usize, comptime fmt: []const u8, args: anytype) runtime.RuntimeError {
        return data.failAtByte(self.state, "msgpack.read", offset, fmt, args);
    }

    fn document(self: *Reader) !Value {
        const b = &self.builder;
        if (self.input.len == 0) return self.fail(0, "expected a value, found end of input", .{});
        while (true) {
            const start = self.pos;
            if (b.depth() != 0 and b.top().kind == .object and b.top().key == null) {
                try b.setKey(try self.key());
                continue;
            }

            const tag = try self.byte(start);
            switch (tag) {
                0x00...0x7f => try self.scalar(.{ .integer = tag }),
                0x80...0x8f => try self.container(start, .object, tag & 0x0f),
                0x90...0x9f => try self.container(start, .array, tag & 0x0f),
                0xa0...0xbf => try self.stringValue(start, tag & 0x1f),
                0xc0 => try self.scalar(try data.nullValue(self.state)),
                0xc2 => try self.scalar(.{ .boolean = false }),
                0xc3 => try self.scalar(.{ .boolean = true }),
                0xc4, 0xd9 => try self.stringValue(start, try self.int(start, u8)),
                0xc5, 0xda => try self.stringValue(start, try self.int(start, u16)),
                0xc6, 0xdb => try self.stringValue(start, try self.int(start, u32)),
                0xc7, 0xc8, 0xc9, 0xd4...0xd8 => try self.extension(start, tag),
                0xca => try self.scalar(.{ .number = @as(f32, @bitCast(try self.int(start, u32))) }),
                0xcb => try self.scalar(.{ .number = @bitCast(try self.int(start, u64)) }),
                0xcc => try self.scalar(.{ .integer = try self.int(start, u8) }),
                0xcd => try self.scalar(.{ .integer = try self.int(start, u16) }),
                0xce => try self.scalar(.{ .integer = try self.int(start, u32) }),
                0xcf => {
                    const value = try self.int(start, u64);
                    try self.scalar(if (std.math.cast(i64, value)) |integer| .{ .integer = integer } else .{ .number = @floatFromInt(value) });
                },
                0xd0 => try self.scalar(.{ .integer = try self.int(start, i8) }),
                0xd1 => try self.scalar(.{ .integer = try self.int(start, i16) }),
                0xd2 => try self.scalar(.{ .integer = try self.int(start, i32) }),
                0xd3 => try self.scalar(.{ .integer = try self.int(start, i64) }),
                0xdc => try self.container(start, .array, try self.int(start, u16)),
                0xdd => try self.container(start, .array, try self.int(start, u32)),
                0xde => try self.container(start, .object, try self.int(start, u16)),
                0xdf => try self.container(start, .object, try self.int(start, u32)),
                0xe0...0xff => try self.scalar(.{ .integer = @as(i8, @bitCast(tag)) }),
                0xc1 => return self.fail(start, "invalid type byte 0xc1", .{}),
            }

            while (b.depth() != 0 and b.top().remaining == 0) try b.end();
            if (b.depth() == 0) break;
        }
        if (self.pos != self.input.len) return self.fail(self.pos, "trailing data after the value", .{});
        return b.root;
    }

    fn scalar(self: *Reader, value: Value) !void {
        if (self.builder.depth() != 0) self.builder.top().remaining -= 1;
        try self.builder.append(value);
    }

    fn container(self: *Reader, start: usize, kind: data.Builder.Kind, count: usize) !void {
        const b = &self.builder;
        if (b.depth() == data.max_depth) return self.fail(start, "nesting deeper than {d} levels", .{data.max_depth});
        const min_bytes = if (kind == .object) count *| 2 else count;
        if (min_bytes > self.input.len - self.pos) return self.fail(start, "{s} of {d} entries is longer than the input", .{ if (kind == .object) "map" else "array", count });
        if (b.depth() != 0) b.top().remaining -= 1;
        try b.begin(kind, count);
        b.top().remaining = count;
    }

    fn stringValue(self: *Reader, start: usize, len: usize) !void {
        const bytes = try self.take(start, len);
        if (self.builder.depth() != 0) self.builder.top().remaining -= 1;
        try self.builder.appendString(bytes);
    }

    fn key(self: *Reader) ![]const u8 {
        const start = self.pos;
        const tag = try self.byte(start);
        const len: usize = switch (tag) {
            0xa0...0xbf => tag & 0x1f,
            0xc4, 0xd9 => try self.int(start, u8),
            0xc5, 0xda => try self.int(start, u16),
            0xc6, 0xdb => try self.int(start, u32),
            else => return self.fail(start, "map keys must be strings", .{}),
        };
        return self.take(start, len);
    }

    fn extension(self: *Reader, start: usize, tag: u8) !void {
        const len: usize = switch (tag) {
            0xd4 => 1,
            0xd5 => 2,
            0xd6 => 4,
            0xd7 => 8,
            0xd8 => 16,
            0xc7 => try self.int(start, u8),
            0xc8 => try self.int(start, u16),
            else => try self.int(start, u32),
        };
        const type_id: i8 = @bitCast(try self.byte(start));
        const payload = try self.take(start, len);
        const value = if (type_id == -1)
            try datetime.toLua(self.state, try self.timestamp(start, payload))
        else
            try data.newExtension(self.state, .{ .type_id = type_id, .data = payload });
        try self.scalar(value);
    }

    fn timestamp(self: *Reader, start: usize, payload: []const u8) !datetime.DateTime {
        var seconds: i64 = undefined;
        var nanosecond: u64 = 0;
        switch (payload.len) {
            4 => seconds = std.mem.readInt(u32, payload[0..4], .big),
            8 => {
                const packed_value = std.mem.readInt(u64, payload[0..8], .big);
                nanosecond = packed_value >> 34;
                seconds = @intCast(packed_value & ((1 << 34) - 1));
            },
            12 => {
                nanosecond = std.mem.readInt(u32, payload[0..4], .big);
                seconds = std.mem.readInt(i64, payload[4..12], .big);
            },
            else => return self.fail(start, "timestamp of {d} bytes; expected 4, 8, or 12", .{payload.len}),
        }
        if (nanosecond > 999_999_999) return self.fail(start, "timestamp nanoseconds out of range", .{});
        if (@abs(seconds) > datetime.max_unix_seconds) return self.fail(start, "timestamp is out of range", .{});
        return datetime.DateTime.fromUnix(seconds, @intCast(nanosecond));
    }

    fn byte(self: *Reader, start: usize) !u8 {
        if (self.pos == self.input.len) return self.fail(start, "unexpected end of input", .{});
        self.pos += 1;
        return self.input[self.pos - 1];
    }

    fn int(self: *Reader, start: usize, comptime T: type) !T {
        const bytes = try self.take(start, @sizeOf(T));
        return std.mem.readInt(T, bytes[0..@sizeOf(T)], .big);
    }

    fn take(self: *Reader, start: usize, len: usize) ![]const u8 {
        if (len > self.input.len - self.pos) return self.fail(start, "unexpected end of input", .{});
        const bytes = self.input[self.pos..][0..len];
        self.pos += len;
        return bytes;
    }
};

pub fn extension(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = "msgpack.extension";
    const type_arg = runtime.argValue(state, thread, op, 0);
    const integer = runtime.toInteger(type_arg) orelse return state.failArgumentType(name, 1, "integer", type_arg);
    const type_id = std.math.cast(i8, integer) orelse return state.failArgumentMessage(name, 1, "type must be between -128 and 127");
    if (type_id == -1) return state.failArgumentMessage(name, 1, "type -1 is the timestamp extension; use a datetime");
    const payload = runtime.argValue(state, thread, op, 1);
    if (payload != .string) return state.failArgumentType(name, 2, "string", payload);
    try data.returnValue(state, thread, op, try data.newExtension(state, .{ .type_id = type_id, .data = payload.string.bytes() }));
}

pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0) return state.failArgumentMessage("msgpack.write", 1, "value expected");
    var writer: Writer = .{ .walker = .init(state, "msgpack.write"), .value = runtime.argValue(state, thread, op, 0) };
    try data.returnEncoded(state, thread, op, "msgpack.write", &writer, Writer.encode);
}

const Writer = struct {
    walker: data.Walker,
    value: Value,

    fn encode(self: *Writer, out: *std.Io.Writer) !void {
        try self.writeValue(out, self.value);
    }

    fn writeValue(self: *Writer, out: *std.Io.Writer, value: Value) anyerror!void {
        try self.walker.visit(value);
        switch (value) {
            .nil => try out.writeByte(0xc0),
            .boolean => |boolean| try out.writeByte(if (boolean) 0xc3 else 0xc2),
            .integer => |integer| try writeInteger(out, integer),
            .number => |number| {
                const narrow: f32 = @floatCast(number);
                if (@as(f64, narrow) == number) {
                    try out.writeByte(0xca);
                    try out.writeInt(u32, @bitCast(narrow), .big);
                } else {
                    try out.writeByte(0xcb);
                    try out.writeInt(u64, @bitCast(number), .big);
                }
            },
            .string => |string| try self.writeString(out, string.bytes()),
            .table => |table| try self.writeTable(out, table),
            else => return self.walker.failValue(value),
        }
    }

    fn writeTable(self: *Writer, out: *std.Io.Writer, table: *Table) anyerror!void {
        switch (try self.walker.enter(table)) {
            .null => try out.writeByte(0xc0),
            .datetime => |value| {
                if (value.date == null or value.time == null or value.offset == null) return self.walker.fail("a MessagePack timestamp needs a date, a time, and an offset", .{});
                try writeTimestamp(out, value.unixSeconds(), value.time.?.nanosecond);
            },
            .extension => |value| {
                try self.writeExtensionHeader(out, value.data.len);
                try out.writeByte(@bitCast(value.type_id));
                try out.writeAll(value.data);
            },
            .array => |len| {
                defer self.walker.leave();
                try self.writeHeader(out, len, 0x90, 15, 0xdc);
                for (1..len + 1) |index| {
                    self.walker.step(.{ .index = index });
                    try self.writeValue(out, table.get(.{ .integer = @intCast(index) }));
                }
            },
            .object => |count| {
                defer self.walker.leave();
                try self.writeHeader(out, count, 0x80, 15, 0xde);
                for (table.entries()) |entry| {
                    if (entry.value == .nil) continue;
                    const name = entry.key.string.bytes();
                    self.walker.step(.{ .key = name });
                    try self.writeString(out, name);
                    try self.writeValue(out, entry.value);
                }
            },
        }
    }

    fn writeString(self: *Writer, out: *std.Io.Writer, bytes: []const u8) !void {
        if (std.unicode.utf8ValidateSlice(bytes)) {
            if (bytes.len <= 31) {
                try out.writeByte(0xa0 | @as(u8, @intCast(bytes.len)));
            } else if (bytes.len <= std.math.maxInt(u8)) {
                try out.writeByte(0xd9);
                try out.writeByte(@intCast(bytes.len));
            } else {
                try self.writeHeader(out, bytes.len, 0, 0, 0xda);
            }
        } else if (bytes.len <= std.math.maxInt(u8)) {
            try out.writeByte(0xc4);
            try out.writeByte(@intCast(bytes.len));
        } else {
            try self.writeHeader(out, bytes.len, 0, 0, 0xc5);
        }
        try out.writeAll(bytes);
    }

    /// Writes the fixed form `fix | len` when `len <= fix_max`, else `tag16` or the 32-bit tag after it.
    fn writeHeader(self: *Writer, out: *std.Io.Writer, len: usize, fix: u8, fix_max: usize, tag16: u8) !void {
        if (fix_max != 0 and len <= fix_max) {
            try out.writeByte(fix | @as(u8, @intCast(len)));
        } else if (len <= std.math.maxInt(u16)) {
            try out.writeByte(tag16);
            try out.writeInt(u16, @intCast(len), .big);
        } else if (len <= std.math.maxInt(u32)) {
            try out.writeByte(tag16 + 1);
            try out.writeInt(u32, @intCast(len), .big);
        } else {
            return self.walker.fail("length {d} does not fit in MessagePack", .{len});
        }
    }

    fn writeExtensionHeader(self: *Writer, out: *std.Io.Writer, len: usize) !void {
        switch (len) {
            1 => try out.writeByte(0xd4),
            2 => try out.writeByte(0xd5),
            4 => try out.writeByte(0xd6),
            8 => try out.writeByte(0xd7),
            16 => try out.writeByte(0xd8),
            else => if (len <= std.math.maxInt(u8)) {
                try out.writeByte(0xc7);
                try out.writeByte(@intCast(len));
            } else {
                try self.writeHeader(out, len, 0, 0, 0xc8);
            },
        }
    }
};

fn writeTimestamp(out: *std.Io.Writer, seconds: i64, nanosecond: u32) !void {
    if (seconds >= 0 and seconds < 1 << 34) {
        if (nanosecond == 0 and seconds < 1 << 32) {
            try out.writeAll("\xd6\xff");
            try out.writeInt(u32, @intCast(seconds), .big);
        } else {
            try out.writeAll("\xd7\xff");
            try out.writeInt(u64, @as(u64, nanosecond) << 34 | @as(u64, @intCast(seconds)), .big);
        }
        return;
    }
    try out.writeAll("\xc7\x0c\xff");
    try out.writeInt(u32, nanosecond, .big);
    try out.writeInt(i64, seconds, .big);
}

fn writeInteger(out: *std.Io.Writer, value: i64) !void {
    if (value >= 0) {
        if (value <= 0x7f) return out.writeByte(@intCast(value));
        if (value <= std.math.maxInt(u8)) return writeTagged(out, 0xcc, u8, @intCast(value));
        if (value <= std.math.maxInt(u16)) return writeTagged(out, 0xcd, u16, @intCast(value));
        if (value <= std.math.maxInt(u32)) return writeTagged(out, 0xce, u32, @intCast(value));
        return writeTagged(out, 0xcf, u64, @intCast(value));
    }
    if (value >= -32) return out.writeByte(@bitCast(@as(i8, @intCast(value))));
    if (value >= std.math.minInt(i8)) return writeTagged(out, 0xd0, i8, @intCast(value));
    if (value >= std.math.minInt(i16)) return writeTagged(out, 0xd1, i16, @intCast(value));
    if (value >= std.math.minInt(i32)) return writeTagged(out, 0xd2, i32, @intCast(value));
    return writeTagged(out, 0xd3, i64, value);
}

fn writeTagged(out: *std.Io.Writer, tag: u8, comptime T: type, value: T) !void {
    try out.writeByte(tag);
    try out.writeInt(T, value, .big);
}
