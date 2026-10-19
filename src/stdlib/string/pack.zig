const std = @import("std");
const compile = @import("../../compile.zig");
const runtime = @import("../../runtime.zig");
const call_mod = @import("../../runtime/call.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;

pub fn pack(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const pack_format = try state.expectArgumentString(thread, op, "string.pack", 0);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    var arg: u32 = 1;
    var config = PackConfig{};
    var index: usize = 0;
    while (index < pack_format.len) {
        const code = pack_format[index];
        if (std.ascii.isWhitespace(code)) {
            index += 1;
            continue;
        }
        if (code == '<') {
            config.endian = .little;
            index += 1;
            continue;
        }
        if (code == '>') {
            config.endian = .big;
            index += 1;
            continue;
        }
        if (code == '=') {
            config.endian = nativeEndian();
            index += 1;
            continue;
        }
        if (code == '!') {
            try parsePackMaxAlign(state, pack_format, &index, &config);
            index += 1;
            continue;
        }
        if (code == 'X') {
            index += 1;
            const next = try parsePackNextOption(state, pack_format, &index);
            const padding = try packAlignmentPadding(state, out.items.len, next, config.max_align);
            try ensurePackLength(state, out.items.len, padding);
            try out.appendNTimes(state.allocator, 0, padding);
            index += 1;
            continue;
        }

        const item = try parsePackOption(state, pack_format, &index, false);
        if (item.kind != .fixed_string and item.kind != .zero_string and item.kind != .padding) {
            const padding = try packAlignmentPadding(state, out.items.len, item, config.max_align);
            try ensurePackLength(state, out.items.len, padding);
            try out.appendNTimes(state.allocator, 0, padding);
        }
        switch (item.kind) {
            .padding => {
                try ensurePackLength(state, out.items.len, 1);
                try out.append(state.allocator, 0);
            },
            .fixed_string => {
                try ensurePackLength(state, out.items.len, item.size);
                const value = try state.expectArgumentString(thread, op, "string.pack", arg);
                arg += 1;
                if (value.len > item.size) return state.fail("string longer than given size");
                try out.appendSlice(state.allocator, value);
                try out.appendNTimes(state.allocator, 0, item.size - value.len);
            },
            .zero_string => {
                const value = try state.expectArgumentString(thread, op, "string.pack", arg);
                arg += 1;
                if (std.mem.indexOfScalar(u8, value, 0) != null) return state.fail("string contains zeros");
                try ensurePackLength(state, out.items.len, value.len + 1);
                try out.appendSlice(state.allocator, value);
                try out.append(state.allocator, 0);
            },
            .size_string => {
                const value = try state.expectArgumentString(thread, op, "string.pack", arg);
                arg += 1;
                if (!packUnsignedFits(@intCast(value.len), item.size)) return state.fail("string length does not fit in given size");
                try ensurePackLength(state, out.items.len, item.size + value.len);
                try appendPackedUnsigned(state, &out, @intCast(value.len), item.size, config.endian);
                try out.appendSlice(state.allocator, value);
            },
            .integer => {
                const value = runtime.argValue(state, thread, op, arg);
                arg += 1;
                try appendPackedInteger(state, &out, value, item, config.endian);
            },
            .float => {
                const value = runtime.argValue(state, thread, op, arg);
                arg += 1;
                try appendPackedFloat(state, &out, value, item, config.endian);
            },
        }
        index += 1;
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(out.items) }});
}

pub fn packsize(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const pack_format = try state.expectArgumentString(thread, op, "string.packsize", 0);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = @intCast(try packFormatSize(state, pack_format)) }});
}

pub fn unpack(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const pack_format = try state.expectArgumentString(thread, op, "string.unpack", 0);
    const data = try state.expectArgumentString(thread, op, "string.unpack", 1);
    var pos = try unpackInitialPosition(state, data.len, try state.optionalArgumentInteger(thread, op, "string.unpack", 2, 1));
    var config = PackConfig{};
    var values = std.ArrayList(Value).empty;
    defer values.deinit(state.allocator);
    var index: usize = 0;
    while (index < pack_format.len) {
        const code = pack_format[index];
        if (std.ascii.isWhitespace(code)) {
            index += 1;
            continue;
        }
        if (code == '<') {
            config.endian = .little;
            index += 1;
            continue;
        }
        if (code == '>') {
            config.endian = .big;
            index += 1;
            continue;
        }
        if (code == '=') {
            config.endian = nativeEndian();
            index += 1;
            continue;
        }
        if (code == '!') {
            try parsePackMaxAlign(state, pack_format, &index, &config);
            index += 1;
            continue;
        }
        if (code == 'X') {
            index += 1;
            const next = try parsePackNextOption(state, pack_format, &index);
            pos += try packAlignmentPadding(state, pos, next, config.max_align);
            if (pos > data.len) return state.failArgumentMessage("string.unpack", 2, "data string too short");
            index += 1;
            continue;
        }

        const item = try parsePackOption(state, pack_format, &index, false);
        if (item.kind != .fixed_string and item.kind != .zero_string and item.kind != .padding) {
            pos += try packAlignmentPadding(state, pos, item, config.max_align);
        }
        if (!call_mod.nativeStackFits(state, thread, op, values.items.len + 2)) return state.failLibrary("stack overflow (too many results)");
        switch (item.kind) {
            .padding => {
                if (pos + 1 > data.len) return state.failArgumentMessage("string.unpack", 2, "data string too short");
                pos += 1;
            },
            .fixed_string => {
                if (pos + item.size > data.len) return state.failArgumentMessage("string.unpack", 2, "data string too short");
                try values.append(state.allocator, .{ .string = try state.strings.intern(data[pos .. pos + item.size]) });
                pos += item.size;
            },
            .zero_string => {
                const relative_end = std.mem.indexOfScalar(u8, data[pos..], 0) orelse return state.failArgumentMessage("string.unpack", 2, "unfinished string for format 'z'");
                try values.append(state.allocator, .{ .string = try state.strings.intern(data[pos .. pos + relative_end]) });
                pos += relative_end + 1;
            },
            .size_string => {
                if (pos + item.size > data.len) return state.failArgumentMessage("string.unpack", 2, "data string too short");
                const string_len = try unpackUnsignedLength(state, data[pos .. pos + item.size], config.endian);
                pos += item.size;
                if (pos + string_len > data.len) return state.failArgumentMessage("string.unpack", 2, "data string too short");
                try values.append(state.allocator, .{ .string = try state.strings.intern(data[pos .. pos + string_len]) });
                pos += string_len;
            },
            .integer => {
                if (pos + item.size > data.len) return state.failArgumentMessage("string.unpack", 2, "data string too short");
                try values.append(state.allocator, try unpackIntegerValue(state, data[pos .. pos + item.size], item, config.endian));
                pos += item.size;
            },
            .float => {
                if (pos + item.size > data.len) return state.failArgumentMessage("string.unpack", 2, "data string too short");
                try values.append(state.allocator, unpackFloatValue(data[pos .. pos + item.size], item, config.endian));
                pos += item.size;
            },
        }
        index += 1;
    }
    try values.append(state.allocator, .{ .integer = @intCast(pos + 1) });
    try state.returnValues(thread, op.base, op.return_count, values.items);
}

const Endian = enum { little, big };

const PackConfig = struct {
    endian: Endian = nativeEndian(),
    max_align: usize = 1,
};

const PackItemKind = enum {
    integer,
    float,
    fixed_string,
    zero_string,
    size_string,
    padding,
};

const PackItem = struct {
    code: u8,
    kind: PackItemKind,
    size: usize,
    signed: bool = false,
    align_size: usize = 1,
};

const pack_max_size: usize = 16;
const native_max_align: usize = 8;
const pack_max_result_len: usize = @min(std.math.maxInt(usize), std.math.maxInt(i64));

fn nativeEndian() Endian {
    return switch (@import("builtin").target.cpu.arch.endian()) {
        .little => .little,
        .big => .big,
    };
}

fn packFormatSize(state: *State, pack_format: []const u8) !usize {
    var total: usize = 0;
    var config = PackConfig{};
    var index: usize = 0;
    while (index < pack_format.len) {
        const code = pack_format[index];
        if (std.ascii.isWhitespace(code)) {
            index += 1;
            continue;
        }
        if (code == '<' or code == '>' or code == '=') {
            index += 1;
            continue;
        }
        if (code == '!') {
            try parsePackMaxAlign(state, pack_format, &index, &config);
            index += 1;
            continue;
        }
        if (code == 'X') {
            index += 1;
            const next = try parsePackNextOption(state, pack_format, &index);
            total = try addPackSize(state, total, try packAlignmentPadding(state, total, next, config.max_align));
            index += 1;
            continue;
        }

        const item = try parsePackOption(state, pack_format, &index, false);
        if (item.kind == .zero_string or item.kind == .size_string) return state.fail("variable-length format");
        if (item.kind != .fixed_string and item.kind != .padding) total = try addPackSize(state, total, try packAlignmentPadding(state, total, item, config.max_align));
        total = try addPackSize(state, total, item.size);
        index += 1;
    }
    return total;
}

fn parsePackMaxAlign(state: *State, pack_format: []const u8, index: *usize, config: *PackConfig) !void {
    const parsed = try parsePackDecimal(state, pack_format, index);
    const max_align = parsed orelse native_max_align;
    if (max_align < 1 or max_align > pack_max_size) return state.fail("out of limits");
    if (!isPowerOfTwo(max_align)) return state.fail("not power of 2");
    config.max_align = max_align;
}

fn parsePackNextOption(state: *State, pack_format: []const u8, index: *usize) !PackItem {
    if (index.* >= pack_format.len or std.ascii.isWhitespace(pack_format[index.*])) return state.fail("invalid next option");
    if (pack_format[index.*] == 'X' or pack_format[index.*] == '<' or pack_format[index.*] == '>' or pack_format[index.*] == '=' or pack_format[index.*] == '!') return state.fail("invalid next option");
    const item = try parsePackOption(state, pack_format, index, true);
    return switch (item.kind) {
        .integer, .float => item,
        else => state.fail("invalid next option"),
    };
}

fn parsePackOption(state: *State, pack_format: []const u8, index: *usize, next_option: bool) !PackItem {
    const code = pack_format[index.*];
    return switch (code) {
        'b', 'B' => .{ .code = code, .kind = .integer, .size = 1, .signed = code == 'b', .align_size = 1 },
        'h', 'H' => .{ .code = code, .kind = .integer, .size = @sizeOf(c_short), .signed = code == 'h', .align_size = @sizeOf(c_short) },
        'l', 'L' => .{ .code = code, .kind = .integer, .size = @sizeOf(c_long), .signed = code == 'l', .align_size = @sizeOf(c_long) },
        'j', 'J' => .{ .code = code, .kind = .integer, .size = @sizeOf(i64), .signed = code == 'j', .align_size = @sizeOf(i64) },
        'T' => .{ .code = code, .kind = .integer, .size = @sizeOf(usize), .signed = false, .align_size = @sizeOf(usize) },
        'i', 'I' => blk: {
            const size = try parsePackIntegerSize(state, pack_format, index, next_option);
            break :blk .{ .code = code, .kind = .integer, .size = size, .signed = code == 'i', .align_size = size };
        },
        'f' => .{ .code = code, .kind = .float, .size = 4, .align_size = 4 },
        'd', 'n' => .{ .code = code, .kind = .float, .size = 8, .align_size = 8 },
        'c' => .{ .code = code, .kind = .fixed_string, .size = try parsePackFixedStringSize(state, pack_format, index), .align_size = 1 },
        's' => blk: {
            const size = (try parsePackDecimal(state, pack_format, index)) orelse @sizeOf(usize);
            if (size < 1 or size > pack_max_size) return state.fail("out of limits");
            break :blk .{ .code = code, .kind = .size_string, .size = size, .align_size = size };
        },
        'z' => .{ .code = code, .kind = .zero_string, .size = 0, .align_size = 1 },
        'x' => .{ .code = code, .kind = .padding, .size = 1, .align_size = 1 },
        else => invalidPackOption(state, code),
    };
}

fn parsePackIntegerSize(state: *State, pack_format: []const u8, index: *usize, next_option: bool) !usize {
    const size = (try parsePackDecimal(state, pack_format, index)) orelse @sizeOf(c_int);
    if (size < 1 or size > pack_max_size) {
        if (next_option) return packNextSizeOutOfLimits(state, size);
        return state.fail("out of limits");
    }
    return size;
}

fn parsePackFixedStringSize(state: *State, pack_format: []const u8, index: *usize) !usize {
    const size = (try parsePackDecimal(state, pack_format, index)) orelse return state.fail("missing size");
    if (size > pack_max_result_len) return state.fail("invalid format");
    return size;
}

fn parsePackDecimal(state: *State, pack_format: []const u8, index: *usize) !?usize {
    var value: usize = 0;
    var saw_digit = false;
    while (index.* + 1 < pack_format.len and std.ascii.isDigit(pack_format[index.* + 1])) {
        index.* += 1;
        saw_digit = true;
        value = std.math.mul(usize, value, 10) catch return state.fail("invalid format");
        value = std.math.add(usize, value, pack_format[index.*] - '0') catch return state.fail("invalid format");
    }
    return if (saw_digit) value else null;
}

fn invalidPackOption(state: *State, code: u8) runtime.RuntimeError {
    var message = std.ArrayList(u8).empty;
    defer message.deinit(state.allocator);
    runtime.appendFmt(state.allocator, &message, "invalid format option '{c}'", .{code}) catch return state.fail("invalid format option");
    return state.fail(message.items);
}

fn packNextSizeOutOfLimits(state: *State, size: usize) runtime.RuntimeError {
    var message = std.ArrayList(u8).empty;
    defer message.deinit(state.allocator);
    runtime.appendFmt(state.allocator, &message, "({d}) out of limits [1,16]", .{size}) catch return state.fail("out of limits");
    return state.fail(message.items);
}

fn packIntegerDoesNotFit(state: *State, size: usize) runtime.RuntimeError {
    var message = std.ArrayList(u8).empty;
    defer message.deinit(state.allocator);
    runtime.appendFmt(state.allocator, &message, "{d}-byte integer does not fit", .{size}) catch return state.fail("integer does not fit");
    return state.fail(message.items);
}

fn addPackSize(state: *State, current: usize, add: usize) !usize {
    const total = std.math.add(usize, current, add) catch return state.fail("too large");
    if (total > pack_max_result_len) return state.fail("too large");
    return total;
}

fn ensurePackLength(state: *State, current: usize, add: usize) !void {
    const total = std.math.add(usize, current, add) catch return state.fail("too long");
    if (total > pack_max_result_len) return state.fail("too long");
}

fn packAlignmentPadding(state: *State, pos: usize, item: PackItem, max_align: usize) !usize {
    const alignment = try packOptionAlignment(state, item, max_align);
    if (alignment <= 1) return 0;
    return (alignment - (pos % alignment)) % alignment;
}

fn packOptionAlignment(state: *State, item: PackItem, max_align: usize) !usize {
    if (max_align <= 1 or item.align_size <= 1) return 1;
    const alignment = @min(item.align_size, max_align);
    if (!isPowerOfTwo(alignment)) return state.fail("not power of 2");
    return alignment;
}

fn isPowerOfTwo(value: usize) bool {
    return value != 0 and (value & (value - 1)) == 0;
}

fn appendPackedInteger(state: *State, out: *std.ArrayList(u8), value: Value, item: PackItem, endian: Endian) !void {
    const integer = runtime.toInteger(value) orelse return state.fail("number has no integer representation");
    if (item.signed) {
        if (!packSignedFits(integer, item.size)) return state.fail("integer overflow");
    } else if (!packUnsignedFits(integer, item.size)) {
        return state.fail("unsigned overflow");
    }
    try appendPackedIntegerBits(state, out, @bitCast(integer), item.size, item.signed and integer < 0, endian);
}

fn appendPackedUnsigned(state: *State, out: *std.ArrayList(u8), value: u64, size: usize, endian: Endian) !void {
    try appendPackedIntegerBits(state, out, value, size, false, endian);
}

fn appendPackedIntegerBits(state: *State, out: *std.ArrayList(u8), value: u64, size: usize, sign_fill: bool, endian: Endian) !void {
    try ensurePackLength(state, out.items.len, size);
    var bytes: [pack_max_size]u8 = undefined;
    @memset(bytes[0..size], if (sign_fill) 0xff else 0);
    const low_size = @min(size, @sizeOf(u64));
    switch (endian) {
        .little => {
            var byte_index: usize = 0;
            while (byte_index < low_size) : (byte_index += 1) bytes[byte_index] = @truncate(value >> @intCast(byte_index * 8));
        },
        .big => {
            var byte_index: usize = 0;
            while (byte_index < low_size) : (byte_index += 1) bytes[size - 1 - byte_index] = @truncate(value >> @intCast(byte_index * 8));
        },
    }
    try out.appendSlice(state.allocator, bytes[0..size]);
}

fn appendPackedFloat(state: *State, out: *std.ArrayList(u8), value: Value, item: PackItem, endian: Endian) !void {
    try ensurePackLength(state, out.items.len, item.size);
    var bytes: [8]u8 = undefined;
    if (item.code == 'f') {
        std.mem.writeInt(u32, bytes[0..4], @bitCast(@as(f32, @floatCast(try runtime.toNumber(value)))), if (endian == .little) .little else .big);
    } else {
        std.mem.writeInt(u64, bytes[0..8], @bitCast(try runtime.toNumber(value)), if (endian == .little) .little else .big);
    }
    try out.appendSlice(state.allocator, bytes[0..item.size]);
}

fn packSignedFits(value: i64, size: usize) bool {
    if (size >= @sizeOf(i64)) return true;
    const bits: u7 = @intCast(size * 8);
    const min = -(@as(i128, 1) << (bits - 1));
    const max = (@as(i128, 1) << (bits - 1)) - 1;
    const wide: i128 = value;
    return min <= wide and wide <= max;
}

fn packUnsignedFits(value: i64, size: usize) bool {
    if (size >= @sizeOf(i64)) return true;
    if (value < 0) return false;
    const bits: u7 = @intCast(size * 8);
    const max = (@as(i128, 1) << bits) - 1;
    const wide: i128 = value;
    return wide <= max;
}

fn unpackInitialPosition(state: *State, data_len: usize, position: i64) !usize {
    const data_len_i64: i64 = @intCast(data_len);
    const zero_based = if (position > 0) position - 1 else data_len_i64 + position;
    if (zero_based < 0 or zero_based > data_len_i64) return state.failArgumentMessage("string.unpack", 3, "initial position out of string");
    return @intCast(zero_based);
}

fn unpackUnsignedLength(state: *State, bytes: []const u8, endian: Endian) !usize {
    const value = try unpackUnsignedBits(state, bytes, endian);
    if (value > std.math.maxInt(usize)) return state.failArgumentMessage("string.unpack", 2, "data string too short");
    return @intCast(value);
}

fn unpackIntegerValue(state: *State, bytes: []const u8, item: PackItem, endian: Endian) !Value {
    const unsigned = if (item.signed) try unpackSignedBits(state, bytes, endian) else try unpackUnsignedBits(state, bytes, endian);
    return .{ .integer = @bitCast(unsigned) };
}

fn unpackFloatValue(bytes: []const u8, item: PackItem, endian: Endian) Value {
    if (item.code == 'f') return .{ .number = @floatCast(@as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], if (endian == .little) .little else .big)))) };
    return .{ .number = @bitCast(std.mem.readInt(u64, bytes[0..8], if (endian == .little) .little else .big)) };
}

fn unpackSignedBits(state: *State, bytes: []const u8, endian: Endian) !u64 {
    if (bytes.len <= @sizeOf(u64)) {
        const unsigned = unpackLowBits(bytes, endian);
        return @bitCast(signExtend(unsigned, bytes.len));
    }
    const low = unpackExtendedLowBits(bytes, endian);
    const expected: u8 = if ((low & (@as(u64, 1) << 63)) != 0) 0xff else 0;
    if (!extendedBytesAll(bytes, endian, expected)) return packIntegerDoesNotFit(state, bytes.len);
    return low;
}

fn unpackUnsignedBits(state: *State, bytes: []const u8, endian: Endian) !u64 {
    if (bytes.len <= @sizeOf(u64)) return unpackLowBits(bytes, endian);
    if (!extendedBytesAll(bytes, endian, 0)) return packIntegerDoesNotFit(state, bytes.len);
    return unpackExtendedLowBits(bytes, endian);
}

fn unpackLowBits(bytes: []const u8, endian: Endian) u64 {
    var value: u64 = 0;
    switch (endian) {
        .little => {
            for (bytes, 0..) |source_byte, index| value |= @as(u64, source_byte) << @intCast(index * 8);
        },
        .big => {
            for (bytes) |source_byte| value = (value << 8) | source_byte;
        },
    }
    return value;
}

fn unpackExtendedLowBits(bytes: []const u8, endian: Endian) u64 {
    return switch (endian) {
        .little => unpackLowBits(bytes[0..8], endian),
        .big => unpackLowBits(bytes[bytes.len - 8 ..], endian),
    };
}

fn extendedBytesAll(bytes: []const u8, endian: Endian, expected: u8) bool {
    const extra = switch (endian) {
        .little => bytes[8..],
        .big => bytes[0 .. bytes.len - 8],
    };
    for (extra) |source_byte| if (source_byte != expected) return false;
    return true;
}

fn signExtend(value: u64, size: usize) i64 {
    const bits = size * 8;
    if (bits == 64) return @bitCast(value);
    const shift: u6 = @intCast(64 - bits);
    return @as(i64, @bitCast(value << shift)) >> shift;
}
