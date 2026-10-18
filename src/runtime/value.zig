const std = @import("std");
const compile = @import("../compile.zig");
const types = @import("types.zig");
const number_format = @import("number_format.zig");
const static_strings = @import("../stdlib/static_strings.zig");
const table_index = @import("table_index.zig");

const bytecode = compile.bytecode;
const proto_mod = compile.proto;

pub const Value = types.Value;
pub const Thread = types.Thread;
pub const ProtectedCallResult = types.ProtectedCallResult;

pub fn valuesEqual(lhs: Value, rhs: Value) bool {
    return switch (lhs) {
        .nil => rhs == .nil,
        .boolean => |value| rhs == .boolean and rhs.boolean == value,
        .integer => |value| switch (rhs) {
            .integer => |other| value == other,
            .number => |other| if (floatToInteger(other)) |integer| value == integer else false,
            else => false,
        },
        .number => |value| switch (rhs) {
            .integer => |other| if (floatToInteger(value)) |integer| integer == other else false,
            .number => |other| value == other,
            else => false,
        },
        .string => |value| rhs == .string and value.eql(rhs.string),
        .table => |value| rhs == .table and value == rhs.table,
        .userdata => |value| rhs == .userdata and value == rhs.userdata,
        .closure => |value| rhs == .closure and value == rhs.closure,
        .thread => |value| rhs == .thread and value == rhs.thread,
        .coroutine_wrapper => |value| rhs == .coroutine_wrapper and value == rhs.coroutine_wrapper,
        .gmatch_iterator => |value| rhs == .gmatch_iterator and value == rhs.gmatch_iterator,
        .native_print => rhs == .native_print,
        .native_tostring => rhs == .native_tostring,
        .native_getmetatable => rhs == .native_getmetatable,
        .native_setmetatable => rhs == .native_setmetatable,
        .native_rawequal => rhs == .native_rawequal,
        .native_rawget => rhs == .native_rawget,
        .native_rawset => rhs == .native_rawset,
        .native_rawlen => rhs == .native_rawlen,
        .native_next => rhs == .native_next,
        .native_pairs => rhs == .native_pairs,
        .native_ipairs => rhs == .native_ipairs,
        .native_ipairs_iter => rhs == .native_ipairs_iter,
        .native_table_create => rhs == .native_table_create,
        .native_select => rhs == .native_select,
        .native_assert => rhs == .native_assert,
        .native_error => rhs == .native_error,
        .native_pcall => rhs == .native_pcall,
        .native_xpcall => rhs == .native_xpcall,
        .native_collectgarbage => rhs == .native_collectgarbage,
        .native_debug_traceback => rhs == .native_debug_traceback,
        .native_coroutine_create => rhs == .native_coroutine_create,
        .native_coroutine_resume => rhs == .native_coroutine_resume,
        .native_coroutine_yield => rhs == .native_coroutine_yield,
        .native_coroutine_status => rhs == .native_coroutine_status,
        .native_coroutine_running => rhs == .native_coroutine_running,
        .native_coroutine_isyieldable => rhs == .native_coroutine_isyieldable,
        .native_coroutine_close => rhs == .native_coroutine_close,
        .native_coroutine_wrap => rhs == .native_coroutine_wrap,
        .native => |native| rhs == .native and rhs.native == native,
        .api_callback => |id| rhs == .api_callback and rhs.api_callback == id,
    };
}

pub fn hashValue(value: Value) u64 {
    return switch (value) {
        .integer => |payload| hashInteger(payload),
        .number => |payload| if (floatToInteger(payload)) |integer| hashInteger(integer) else mix(@as(u64, @bitCast(payload)) ^ 0x3c6ef372fe94f82b),
        .string => |payload| payload.tableHash(),
        .table, .gmatch_iterator => |payload| hashPointer(5, payload),
        .userdata => |payload| hashPointer(6, payload),
        .closure => |payload| hashPointer(7, payload),
        .thread => |payload| hashPointer(9, payload),
        .coroutine_wrapper => |payload| hashPointer(10, payload),
        .boolean => |payload| mix(@as(u64, @intFromBool(payload)) + 0x9e3779b97f4a7c15),
        .native => |payload| mix(@as(u64, @intFromEnum(payload)) +% (40 << 56)),
        .api_callback => |id| mix(@as(u64, id) +% (41 << 56)),
        else => mix(@as(u64, @intFromEnum(std.meta.activeTag(value))) << 48),
    };
}

pub fn hashString(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0x2d358dccaa6c78a5, bytes);
}

inline fn mix(input: u64) u64 {
    var x = input;
    x ^= x >> 30;
    x *%= 0xbf58476d1ce4e5b9;
    x ^= x >> 27;
    x *%= 0x94d049bb133111eb;
    x ^= x >> 31;
    return x;
}

inline fn hashInteger(value: i64) u64 {
    return mix(@bitCast(value));
}

inline fn hashPointer(comptime tag: u8, pointer: anytype) u64 {
    return mix(@as(u64, @intFromPtr(pointer)) ^ (@as(u64, tag) << 56));
}

pub fn truthy(value: Value) bool {
    return switch (value) {
        .nil => false,
        .boolean => |boolean| boolean,
        else => true,
    };
}

pub fn toInteger(value: Value) ?i64 {
    return switch (value) {
        .integer => |integer| integer,
        .string => |string| parseIntegerStrict(string.bytes()),
        else => null,
    };
}

/// Like `lua_tointegerx`: floats and numeric strings convert only when exactly integral.
pub fn coerceToInteger(value: Value) ?i64 {
    return switch (value) {
        .integer => |integer| integer,
        .number => |number| floatToInteger(number),
        .string => |string| parseIntegerStrict(string.bytes()) orelse if (parseLuaNumber(string.bytes())) |number| floatToInteger(number) else |_| null,
        else => null,
    };
}

pub fn toNumber(value: Value) !f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .number => |number| number,
        .string => |string| parseLuaNumber(string.bytes()),
        else => error.RuntimeError,
    };
}

pub fn toNumberMaybe(value: Value) ?f64 {
    return toNumber(value) catch null;
}

pub fn luaStringLike(value: Value) bool {
    return switch (value) {
        .integer, .number, .string => true,
        else => false,
    };
}

pub fn indexErrorMessage(value: Value) []const u8 {
    return switch (value) {
        .integer, .number => "attempt to index a number value",
        .string => "attempt to index a string value",
        .boolean => "attempt to index a boolean value",
        .nil => "attempt to index a nil value",
        .userdata => "attempt to index a userdata value",
        else => "attempt to index a non-table value",
    };
}

pub fn callErrorMessage(value: Value) []const u8 {
    return switch (value) {
        .integer, .number => "attempt to call a number value",
        .string => "attempt to call a string value",
        .boolean => "attempt to call a boolean value",
        .nil => "attempt to call a nil value",
        .table => "attempt to call a table value",
        .userdata => "attempt to call a userdata value",
        else => "attempt to call a non-function value",
    };
}

pub fn nativeHookName(value: Value) ?[]const u8 {
    return switch (value) {
        .native_print => "print",
        .native_tostring => "tostring",
        .native_getmetatable => "getmetatable",
        .native_setmetatable => "setmetatable",
        .native_rawequal => "rawequal",
        .native_rawget => "rawget",
        .native_rawset => "rawset",
        .native_rawlen => "rawlen",
        .native_next => "next",
        .native_pairs => "pairs",
        .native_ipairs => "ipairs",
        .native_ipairs_iter => "ipairs iterator",
        .native_table_create => "create",
        .native_select => "select",
        .native_assert => "assert",
        .native_error => "error",
        .native_pcall => "pcall",
        .native_xpcall => "xpcall",
        .native_collectgarbage => "collectgarbage",
        .native_debug_traceback => "traceback",
        .native_coroutine_create => "create",
        .native_coroutine_resume => "resume",
        .native_coroutine_yield => "yield",
        .native_coroutine_status => "status",
        .native_coroutine_running => "running",
        .native_coroutine_isyieldable => "isyieldable",
        .native_coroutine_close => "close",
        .native_coroutine_wrap => "wrap",
        .native => |native| shortNativeName(native.name()),
        else => null,
    };
}

pub fn shortNativeName(name: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.');
    const colon = std.mem.lastIndexOfScalar(u8, name, ':');
    const start = if (dot) |dot_index| if (colon) |colon_index| @max(dot_index, colon_index) + 1 else dot_index + 1 else if (colon) |colon_index| colon_index + 1 else 0;
    return name[start..];
}

pub fn debugValueTypeName(value: Value) []const u8 {
    return switch (value) {
        .nil => "nil",
        .boolean => "boolean",
        .integer => "integer",
        .number => "number",
        .string => "string",
        .table => "table",
        .userdata => "userdata",
        .thread => "thread",
        .closure,
        .coroutine_wrapper,
        .gmatch_iterator,
        .native_print,
        .native_tostring,
        .native_getmetatable,
        .native_setmetatable,
        .native_rawequal,
        .native_rawget,
        .native_rawset,
        .native_rawlen,
        .native_next,
        .native_pairs,
        .native_ipairs,
        .native_ipairs_iter,
        .native_table_create,
        .native_select,
        .native_assert,
        .native_error,
        .native_pcall,
        .native_xpcall,
        .native_collectgarbage,
        .native_debug_traceback,
        .native_coroutine_create,
        .native_coroutine_resume,
        .native_coroutine_yield,
        .native_coroutine_status,
        .native_coroutine_running,
        .native_coroutine_isyieldable,
        .native_coroutine_close,
        .native_coroutine_wrap,
        .native,
        .api_callback,
        => "function",
    };
}

pub fn appendLuaString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    switch (value) {
        .integer, .number, .string => try appendValue(allocator, out, value),
        else => return error.RuntimeError,
    }
}

/// Must run before any closure of the tree runs. Prepared prototypes are never
/// written again, so snapshot workers may share them.
pub fn prepareProtoTree(proto: *proto_mod.Proto) !void {
    if (proto.runtime_prepared) return;
    for (proto.children.items) |child| try prepareProtoTree(child);
    const values = try proto.arena.allocator().alloc(Value, proto.constants.items.len);
    for (proto.constants.items, values) |constant, *value| {
        value.* = switch (constant) {
            .nil => .nil,
            .boolean => |boolean| .{ .boolean = boolean },
            .integer => |lexeme| parseIntegerLiteral(lexeme) catch .{ .string = static_strings.get("") },
            .number => |lexeme| if (parseLuaNumber(lexeme)) |number| .{ .number = number } else |_| .{ .string = static_strings.get("") },
            .string => .{ .string = static_strings.get("") },
        };
    }
    proto.constant_values = values;
    const hashes = try proto.arena.allocator().alloc(u32, proto.constants.items.len);
    for (proto.constants.items, hashes) |constant, *hash| {
        hash.* = if (constant == .string) table_index.hashStringKey(constant.string) else 0;
    }
    proto.constant_hashes = hashes;
    proto.named_vararg_readonly = proto.hasReadOnlyNamedVararg();
    const instructions = proto.instructions.items;
    const last_stops = instructions.len != 0 and switch (instructions[instructions.len - 1]) {
        .ret, .tail_call, .close => true,
        else => false,
    };
    if (proto.has_to_close_locals) proto.close_exit_jumps = try closeExitJumps(proto);
    proto.fast_loop_entry = last_stops;
    proto.fast_loop_call = proto.fast_loop_entry and !proto.is_vararg and !proto.named_vararg;
    proto.runtime_prepared = true;
}

fn closeExitJumps(proto: *proto_mod.Proto) ![]const u64 {
    const instructions = proto.instructions.items;
    const bits = try proto.arena.allocator().alloc(u64, (instructions.len + 63) / 64);
    @memset(bits, 0);
    for (instructions, 0..) |instruction, index| {
        const offset: bytecode.JumpOffset = switch (instruction) {
            .jmp => |offset| offset,
            inline .compare_branch, .compare_branch_k, .test_op, .test_set, .for_loop, .for_prep, .tfor_prep, .tfor_loop => |op| op.offset,
            else => continue,
        };
        const source = index + 1;
        const target = if (offset >= 0) source + @as(usize, @intCast(offset)) else source -% @as(usize, @intCast(-offset));
        for (proto.locals.items) |local| {
            if (local.to_close and localActiveAt(local, source) and !localActiveAt(local, target)) {
                bits[index / 64] |= @as(u64, 1) << @intCast(index % 64);
                break;
            }
        }
    }
    return bits;
}

pub fn localActiveAt(local: proto_mod.LocalDebug, pc: usize) bool {
    return local.start_pc <= pc and (local.end_pc == 0 or pc < local.end_pc);
}

pub fn parseIntegerLiteral(lexeme: []const u8) !Value {
    if (isHex(lexeme)) {
        var unsigned: u64 = 0;
        for (lexeme[2..]) |byte| unsigned = unsigned *% 16 +% hexValue(byte);
        return .{ .integer = @as(i64, @bitCast(unsigned)) };
    }
    if (std.fmt.parseInt(i64, lexeme, 10)) |integer| {
        return .{ .integer = integer };
    } else |_| {
        return .{ .number = try std.fmt.parseFloat(f64, lexeme) };
    }
}

pub fn parseIntegerStrict(text: []const u8) ?i64 {
    const trimmed = trimAscii(text);
    if (trimmed.len == 0) return null;
    const negative = trimmed[0] == '-';
    const unsigned_text = if (trimmed[0] == '+' or trimmed[0] == '-') trimmed[1..] else trimmed;
    if (unsigned_text.len == 0) return null;
    if (isHex(unsigned_text)) {
        if (unsigned_text.len == 2) return null;
        var unsigned: u64 = 0;
        for (unsigned_text[2..]) |byte| {
            if (!std.ascii.isHex(byte)) return null;
            unsigned = unsigned *% 16 +% hexValue(byte);
        }
        const integer: i64 = @bitCast(unsigned);
        return if (negative) -%integer else integer;
    }
    for (trimmed, 0..) |byte, index| {
        if (index == 0 and (byte == '+' or byte == '-')) continue;
        if (!std.ascii.isDigit(byte)) return null;
    }
    return std.fmt.parseInt(i64, trimmed, 10) catch null;
}

pub fn parseLuaNumber(text: []const u8) !f64 {
    const trimmed = trimAscii(text);
    if (trimmed.len == 0) return error.RuntimeError;
    const negative = trimmed[0] == '-';
    const unsigned_text = if (trimmed[0] == '+' or trimmed[0] == '-') trimmed[1..] else trimmed;
    if (unsigned_text.len == 0) return error.RuntimeError;
    if (isHex(unsigned_text)) {
        const number = try parseHexNumber(unsigned_text);
        return if (negative) -number else number;
    }
    var has_digit = false;
    for (unsigned_text) |byte| {
        if (std.ascii.isDigit(byte)) {
            has_digit = true;
            break;
        }
    }
    if (!has_digit) return error.RuntimeError;
    return std.fmt.parseFloat(f64, trimmed);
}

/// Ports `lua_strx2number`: digits past the 30th significant one only adjust the exponent.
fn parseHexNumber(text: []const u8) !f64 {
    const max_significant_digits = 30;
    var index: usize = 2;
    var value: f64 = 0;
    var exponent: i64 = 0;
    var significant_digits: usize = 0;
    var any_digits = false;
    var seen_dot = false;
    while (index < text.len) : (index += 1) {
        const byte = text[index];
        if (byte == '.') {
            if (seen_dot) break;
            seen_dot = true;
        } else if (std.ascii.isHex(byte)) {
            any_digits = true;
            if (significant_digits > 0 or byte != '0') {
                significant_digits += 1;
                if (significant_digits <= max_significant_digits) {
                    value = value * 16 + @as(f64, @floatFromInt(hexValue(byte)));
                } else {
                    exponent += 1;
                }
            }
            if (seen_dot) exponent -= 1;
        } else break;
    }
    if (!any_digits) return error.RuntimeError;
    exponent *= 4;

    if (index < text.len and (text[index] == 'p' or text[index] == 'P')) {
        index += 1;
        var negative = false;
        if (index < text.len and (text[index] == '+' or text[index] == '-')) {
            negative = text[index] == '-';
            index += 1;
        }
        const exponent_start = index;
        var written: i64 = 0;
        while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {
            written = @min(written * 10 + (text[index] - '0'), 1 << 32);
        }
        if (index == exponent_start) return error.RuntimeError;
        exponent += if (negative) -written else written;
    }
    if (index != text.len) return error.RuntimeError;
    const clamped: i32 = @intCast(std.math.clamp(exponent, -100_000, 100_000));
    return std.math.ldexp(value, clamped);
}

pub fn floatToInteger(number: f64) ?i64 {
    if (!std.math.isFinite(number) or @floor(number) != number) return null;
    const min = @as(f64, @floatFromInt(std.math.minInt(i64)));
    const max = @as(f64, @floatFromInt(std.math.maxInt(i64)));
    if (number < min or number >= max) return null;
    return @intFromFloat(number);
}

pub fn isHex(text: []const u8) bool {
    return text.len >= 3 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X');
}

pub fn trimAscii(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\n\r\x0b\x0c");
}

pub fn arrayIndex(value: Value) ?usize {
    const integer = switch (value) {
        .integer => |integer| integer,
        else => return null,
    };
    if (integer <= 0) return null;
    return std.math.cast(usize, integer);
}

pub fn runtimeArgValue(state: anytype, thread: *Thread, op: bytecode.Call, index: u32) Value {
    _ = state;
    if (index >= op.arg_count) return .nil;
    const frame = thread.frames.items[thread.frames.items.len - 1];
    return thread.stack.items[frame.base + op.base + 1 + index];
}

pub fn argValue(state: anytype, thread: *Thread, op: bytecode.Call, index: u32) Value {
    return runtimeArgValue(state, thread, op, index);
}

pub fn appendValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    switch (value) {
        .nil => try out.appendSlice(allocator, "nil"),
        .boolean => |boolean| try out.appendSlice(allocator, if (boolean) "true" else "false"),
        .integer, .number => {
            var buffer: [max_number_text_len]u8 = undefined;
            try out.appendSlice(allocator, formatNumber(&buffer, value));
        },
        .string => |string| try out.appendSlice(allocator, string.bytes()),
        .table => |table| try appendFmt(allocator, out, "table: 0x{x}", .{@intFromPtr(table)}),
        .userdata => |userdata| try appendFmt(allocator, out, "userdata: 0x{x}", .{@intFromPtr(userdata)}),
        .closure => |closure| try appendFmt(allocator, out, "function: 0x{x}", .{@intFromPtr(closure)}),
        .thread => |thread| try appendFmt(allocator, out, "thread: 0x{x}", .{@intFromPtr(thread)}),
        .coroutine_wrapper => |thread| try appendFmt(allocator, out, "function: 0x{x}", .{@intFromPtr(thread)}),
        .gmatch_iterator => |table| try appendFmt(allocator, out, "function: 0x{x}", .{@intFromPtr(table)}),
        .native_print => try out.appendSlice(allocator, "function: print"),
        .native_tostring => try out.appendSlice(allocator, "function: tostring"),
        .native_getmetatable => try out.appendSlice(allocator, "function: getmetatable"),
        .native_setmetatable => try out.appendSlice(allocator, "function: setmetatable"),
        .native_rawequal => try out.appendSlice(allocator, "function: rawequal"),
        .native_rawget => try out.appendSlice(allocator, "function: rawget"),
        .native_rawset => try out.appendSlice(allocator, "function: rawset"),
        .native_rawlen => try out.appendSlice(allocator, "function: rawlen"),
        .native_next => try out.appendSlice(allocator, "function: next"),
        .native_pairs => try out.appendSlice(allocator, "function: pairs"),
        .native_ipairs => try out.appendSlice(allocator, "function: ipairs"),
        .native_ipairs_iter => try out.appendSlice(allocator, "function: ipairs iterator"),
        .native_table_create => try out.appendSlice(allocator, "function: table.create"),
        .native_select => try out.appendSlice(allocator, "function: select"),
        .native_assert => try out.appendSlice(allocator, "function: assert"),
        .native_error => try out.appendSlice(allocator, "function: error"),
        .native_pcall => try out.appendSlice(allocator, "function: pcall"),
        .native_xpcall => try out.appendSlice(allocator, "function: xpcall"),
        .native_collectgarbage => try out.appendSlice(allocator, "function: collectgarbage"),
        .native_debug_traceback => try out.appendSlice(allocator, "function: debug.traceback"),
        .native_coroutine_create => try out.appendSlice(allocator, "function: coroutine.create"),
        .native_coroutine_resume => try out.appendSlice(allocator, "function: coroutine.resume"),
        .native_coroutine_yield => try out.appendSlice(allocator, "function: coroutine.yield"),
        .native_coroutine_status => try out.appendSlice(allocator, "function: coroutine.status"),
        .native_coroutine_running => try out.appendSlice(allocator, "function: coroutine.running"),
        .native_coroutine_isyieldable => try out.appendSlice(allocator, "function: coroutine.isyieldable"),
        .native_coroutine_close => try out.appendSlice(allocator, "function: coroutine.close"),
        .native_coroutine_wrap => try out.appendSlice(allocator, "function: coroutine.wrap"),
        .api_callback => |id| try appendFmt(allocator, out, "function: host callback {d}", .{id}),
        .native => |native| {
            try out.appendSlice(allocator, "function: ");
            try out.appendSlice(allocator, native.name());
        },
    }
}

pub fn appendNamedValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: Value) !void {
    const address: ?usize = switch (value) {
        .table => |table| @intFromPtr(table),
        .userdata => |userdata| @intFromPtr(userdata),
        .closure => |closure| @intFromPtr(closure),
        .thread => |thread| @intFromPtr(thread),
        .coroutine_wrapper => |thread| @intFromPtr(thread),
        else => null,
    };
    if (address) |ptr| {
        try appendFmt(allocator, out, "{s}: 0x{x}", .{ name, ptr });
    } else {
        try out.appendSlice(allocator, name);
    }
}

pub fn freeProtectedResult(allocator: std.mem.Allocator, result: ProtectedCallResult) void {
    switch (result) {
        .success => |values| allocator.free(values),
        .failure => {},
    }
}

pub fn appendNumber(allocator: std.mem.Allocator, out: *std.ArrayList(u8), number: f64) !void {
    var buffer: [max_number_text_len]u8 = undefined;
    try out.appendSlice(allocator, formatNumber(&buffer, .{ .number = number }));
}

/// Fits the longest f64 rendering (subnormals reach ~343 digits) plus sign and ".0".
pub const max_number_text_len = 400;

/// Formats as `tostring` and concatenation do.
pub fn formatNumber(buffer: *[max_number_text_len]u8, value: Value) []const u8 {
    switch (value) {
        .integer => |integer| return std.fmt.bufPrint(buffer, "{d}", .{integer}) catch unreachable,
        .number => |number| return number_format.formatLuaFloat(buffer[0..number_format.max_lua_float_len], number),
        else => unreachable,
    }
}

pub fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

pub fn hexValue(byte: u8) u32 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => 0,
    };
}

pub fn luaTypeName(value: Value) []const u8 {
    return switch (value) {
        .nil => "nil",
        .boolean => "boolean",
        .integer, .number => "number",
        .string => "string",
        .table => "table",
        .userdata => "userdata",
        .thread => "thread",
        .closure,
        .coroutine_wrapper,
        .gmatch_iterator,
        .native_print,
        .native_tostring,
        .native_getmetatable,
        .native_setmetatable,
        .native_rawequal,
        .native_rawget,
        .native_rawset,
        .native_rawlen,
        .native_next,
        .native_pairs,
        .native_ipairs,
        .native_ipairs_iter,
        .native_table_create,
        .native_select,
        .native_assert,
        .native_error,
        .native_pcall,
        .native_xpcall,
        .native_collectgarbage,
        .native_debug_traceback,
        .native_coroutine_create,
        .native_coroutine_resume,
        .native_coroutine_yield,
        .native_coroutine_status,
        .native_coroutine_running,
        .native_coroutine_isyieldable,
        .native_coroutine_close,
        .native_coroutine_wrap,
        .native,
        .api_callback,
        => "function",
    };
}

pub fn isNativeCallable(value: Value) bool {
    return switch (value) {
        .native_print,
        .native_tostring,
        .native_getmetatable,
        .native_setmetatable,
        .native_rawequal,
        .native_rawget,
        .native_rawset,
        .native_rawlen,
        .native_next,
        .native_pairs,
        .native_ipairs,
        .native_ipairs_iter,
        .native_table_create,
        .native_select,
        .native_assert,
        .native_error,
        .native_pcall,
        .native_xpcall,
        .native_collectgarbage,
        .native_debug_traceback,
        .native_coroutine_create,
        .native_coroutine_resume,
        .native_coroutine_yield,
        .native_coroutine_status,
        .native_coroutine_running,
        .native_coroutine_isyieldable,
        .native_coroutine_close,
        .native_coroutine_wrap,
        .native,
        .api_callback,
        => true,
        else => false,
    };
}

pub fn functionLike(value: Value) bool {
    return switch (value) {
        .closure, .coroutine_wrapper, .gmatch_iterator => true,
        else => isNativeCallable(value),
    };
}
