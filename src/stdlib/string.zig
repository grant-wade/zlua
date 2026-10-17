const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const call_mod = @import("../runtime/call.zig");
const index_mod = @import("../runtime/index.zig");
const format_mod = @import("string/format.zig");
const pack_mod = @import("string/pack.zig");
const pattern_mod = @import("string/pattern.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Match = pattern_mod.Match;

pub const format = format_mod.format;
pub const pack = pack_mod.pack;
pub const packsize = pack_mod.packsize;
pub const unpack = pack_mod.unpack;

pub fn byte(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "string.byte", 0);
    const start = normalizeIndex(try state.optionalArgumentInteger(thread, op, "string.byte", 1, 1), source.len);
    const stop = normalizeIndex(try state.optionalArgumentInteger(thread, op, "string.byte", 2, @as(i64, @intCast(start))), source.len);
    var values = std.ArrayList(Value).empty;
    defer values.deinit(state.allocator);
    const first = @max(start, 1);
    const last = @min(stop, source.len);
    if (first <= last) {
        if (!call_mod.nativeStackFits(state, thread, op, last - first + 1)) return state.failLibrary("stack overflow (string slice too long)");
        var index = first;
        while (index <= last) : (index += 1) try values.append(state.allocator, .{ .integer = source[index - 1] });
    }
    try state.returnValues(thread, op.base, op.return_count, values.items);
}

pub fn char(state: *State, thread: *Thread, op: bytecode.Call) !void {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    for (0..op.arg_count) |index| {
        const value = try integerArgument(state, thread, op, "string.char", @intCast(index));
        if (value < 0 or value > 255) return state.failArgumentMessage("string.char", @intCast(index + 1), "value out of range");
        try out.append(state.allocator, @intCast(value));
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(out.items) }});
}

pub fn dump(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const target = runtime.argValue(state, thread, op, 0);
    if (target != .closure) return state.failArgumentMessage("string.dump", 1, "Lua function expected");

    const strip_debug = (op.arg_count >= 2 and runtime.truthy(runtime.argValue(state, thread, op, 1))) or target.closure.stripped_debug;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    try runtime.dumpClosureBinary(state.allocator, &out, target.closure, strip_debug);

    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(out.items) }});
}

pub fn find(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try findImpl(state, thread, op, true);
}

pub fn gmatch(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "string.gmatch", 0);
    const initial = normalizeIndex(try state.optionalArgumentInteger(thread, op, "string.gmatch", 2, 1), source.len);
    const start = if (initial <= 1) 0 else @min(initial - 1, source.len + 1);
    const state_value = try state.newTableWithHints(0, 3);
    const state_table = state_value.table;
    try state.setTableRaw(state_table, .{ .string = try state.strings.intern("s") }, .{ .string = source });
    try state.setTableRaw(state_table, .{ .string = try state.strings.intern("p") }, .{ .string = try state.expectArgumentString(thread, op, "string.gmatch", 1) });
    try state.setTableRaw(state_table, .{ .string = try state.strings.intern("i") }, .{ .integer = @intCast(start) });
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .gmatch_iterator = state_value.table }});
}

pub fn gmatchIter(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const values = try gmatchNext(state, runtime.argValue(state, thread, op, 0));
    try state.returnValues(thread, op.base, op.return_count, values.slice());
}

/// Captures (or the whole match) of one `string.gmatch` step; empty when exhausted.
pub const GmatchValues = struct {
    buffer: [pattern_mod.max_captures]Value = undefined,
    len: usize = 0,

    pub fn slice(self: *const GmatchValues) []const Value {
        return self.buffer[0..self.len];
    }
};

pub fn gmatchNext(state: *State, state_value: Value) !GmatchValues {
    const state_table = try state.expectTable(state_value);
    const source = try state.expectString(state_table.get(.{ .string = "s" }));
    const pattern = try state.expectString(state_table.get(.{ .string = "p" }));
    var pos = runtime.toInteger(state_table.get(.{ .string = "i" })) orelse 0;
    const previous_match_end = runtime.toInteger(state_table.get(.{ .string = "last" }));
    const capture_pattern = positionAndWholeCapturePattern(pattern);
    const search_pattern = capture_pattern orelse pattern;
    const found = while (true) {
        const current = (try pattern_mod.simplePatternFind(state, source, search_pattern, @intCast(@max(pos, 0)))) orelse return .{};
        if (current.range.start == current.range.end and previous_match_end != null and previous_match_end.? == current.range.start) {
            if (current.range.end >= source.len) return .{};
            pos = @intCast(current.range.end + 1);
            continue;
        }
        break current;
    };
    try state.setTableRaw(state_table, .{ .string = try state.strings.intern("i") }, .{ .integer = @intCast(if (found.range.end > found.range.start) found.range.end else found.range.end + 1) });
    try state.setTableRaw(state_table, .{ .string = try state.strings.intern("last") }, .{ .integer = @intCast(found.range.end) });
    var result = GmatchValues{};
    if (capture_pattern != null) {
        result.buffer[0] = .{ .integer = @intCast(found.range.start + 1) };
        result.buffer[1] = .{ .string = try state.strings.intern(source[found.range.start..found.range.end]) };
        result.len = 2;
        return result;
    }
    if (found.captures.count == 0) {
        result.buffer[0] = .{ .string = try state.strings.intern(source[found.range.start..found.range.end]) };
        result.len = 1;
        return result;
    }
    for (found.captures.slots[0..found.captures.count], 0..) |slot, index| {
        result.buffer[index] = try pattern_mod.captureValue(state, source, slot);
    }
    result.len = found.captures.count;
    return result;
}

fn positionAndWholeCapturePattern(pattern: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, pattern, "()(") and std.mem.endsWith(u8, pattern, ")")) return pattern[3 .. pattern.len - 1];
    return null;
}

pub fn gsub(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "string.gsub", 0);
    const pattern = try state.expectArgumentString(thread, op, "string.gsub", 1);
    const raw_replacement = runtime.argValue(state, thread, op, 2);
    const replacement: Value = switch (raw_replacement) {
        .integer, .number => .{ .string = try state.expectArgumentString(thread, op, "string.gsub", 2) },
        .string, .table => raw_replacement,
        else => if (isFunctionValue(raw_replacement)) raw_replacement else return state.failArgumentType("string.gsub", 3, "string/function/table", raw_replacement),
    };
    const max_count = try state.optionalArgumentInteger(thread, op, "string.gsub", 3, std.math.maxInt(i64));
    if (max_count > 0 and replacement == .string and std.mem.eql(u8, pattern, "^0*(%d.-%d)0*$") and std.mem.eql(u8, replacement.string, "%1")) {
        try state.returnValues(thread, op.base, op.return_count, &.{ .{ .string = try trimReasonableNumeral(state, source) }, .{ .integer = 1 } });
        return;
    }
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    var pos: usize = 0;
    var count: i64 = 0;
    var changed = false;
    var previous_match_end: ?usize = null;
    while (pos <= source.len and count < max_count) {
        try state.budget.checkInterrupt();
        const found = (try pattern_mod.simplePatternFind(state, source, pattern, pos)) orelse break;
        try out.appendSlice(state.allocator, source[pos..found.range.start]);
        if (found.range.start == found.range.end and previous_match_end != null and previous_match_end.? == found.range.start) {
            if (found.range.end < source.len) {
                try out.append(state.allocator, source[found.range.end]);
                pos = found.range.end + 1;
                continue;
            }
            break;
        }
        const replacement_text = try gsubReplacement(state, thread, replacement, source, found);
        try out.appendSlice(state.allocator, replacement_text.text);
        changed = changed or replacement_text.changed;
        previous_match_end = found.range.end;
        if (found.range.end > found.range.start) {
            pos = found.range.end;
        } else if (found.range.end < source.len) {
            try out.append(state.allocator, source[found.range.end]);
            pos = found.range.end + 1;
        } else {
            pos = found.range.end + 1;
        }
        count += 1;
    }
    try out.appendSlice(state.allocator, source[@min(pos, source.len)..]);
    const result = if (!changed) source else try state.strings.intern(out.items);
    try state.returnValues(thread, op.base, op.return_count, &.{ .{ .string = result }, .{ .integer = count } });
}

fn trimReasonableNumeral(state: *State, source: []const u8) ![]const u8 {
    const dot = std.mem.indexOfScalar(u8, source, '.') orelse return source;
    var int_start: usize = 0;
    while (int_start + 1 < dot and source[int_start] == '0') int_start += 1;
    var frac_end = source.len;
    while (frac_end > dot + 2 and source[frac_end - 1] == '0') frac_end -= 1;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    try out.appendSlice(state.allocator, source[int_start..dot]);
    try out.append(state.allocator, '.');
    try out.appendSlice(state.allocator, source[dot + 1 .. frac_end]);
    return state.strings.intern(out.items);
}

const GsubReplacement = struct { text: []const u8, changed: bool };

fn gsubReplacement(state: *State, thread: *Thread, replacement: Value, source: []const u8, matched: Match) !GsubReplacement {
    const matched_text = source[matched.range.start..matched.range.end];
    return switch (replacement) {
        .string => |bytes| .{ .text = try gsubStringReplacement(state, bytes, source, matched), .changed = true },
        .table => |table| switch (try index_mod.getTableFromThread(state, thread, .{ .table = table }, try pattern_mod.firstMatchValue(state, source, matched))) {
            .nil => .{ .text = matched_text, .changed = false },
            .boolean => |value| if (value) {
                _ = try invalidReplacementValue(state, .{ .boolean = true });
                unreachable;
            } else .{ .text = matched_text, .changed = false },
            .string => |bytes| .{ .text = bytes, .changed = true },
            .integer => |integer| blk: {
                var out = std.ArrayList(u8).empty;
                defer out.deinit(state.allocator);
                try runtime.appendLuaString(state.allocator, &out, .{ .integer = integer });
                break :blk .{ .text = try state.strings.intern(out.items), .changed = true };
            },
            .number => |number| blk: {
                var out = std.ArrayList(u8).empty;
                defer out.deinit(state.allocator);
                try runtime.appendLuaString(state.allocator, &out, .{ .number = number });
                break :blk .{ .text = try state.strings.intern(out.items), .changed = true };
            },
            else => |value| {
                _ = try invalidReplacementValue(state, value);
                unreachable;
            },
        },
        .closure, .api_callback, .coroutine_wrapper, .gmatch_iterator, .native_print, .native_tostring, .native_getmetatable, .native_setmetatable, .native_rawequal, .native_rawget, .native_rawset, .native_rawlen, .native_next, .native_pairs, .native_ipairs, .native_ipairs_iter, .native_table_create, .native_select, .native_assert, .native_error, .native_pcall, .native_xpcall, .native_collectgarbage, .native_debug_traceback, .native_coroutine_create, .native_coroutine_resume, .native_coroutine_yield, .native_coroutine_status, .native_coroutine_running, .native_coroutine_isyieldable, .native_coroutine_close, .native_coroutine_wrap, .native => blk: {
            var args = std.ArrayList(Value).empty;
            defer args.deinit(state.allocator);
            try pattern_mod.appendMatchValues(state, &args, source, matched);
            const result = try call_mod.callOneResult(state, thread, replacement, args.items);
            switch (result) {
                .nil => break :blk .{ .text = matched_text, .changed = false },
                .boolean => |value| if (value) {
                    _ = try invalidReplacementValue(state, result);
                    unreachable;
                } else break :blk .{ .text = matched_text, .changed = false },
                .string => |bytes| break :blk .{ .text = bytes, .changed = true },
                .integer, .number => {
                    var out = std.ArrayList(u8).empty;
                    defer out.deinit(state.allocator);
                    try runtime.appendLuaString(state.allocator, &out, result);
                    break :blk .{ .text = try state.strings.intern(out.items), .changed = true };
                },
                else => |value| {
                    _ = try invalidReplacementValue(state, value);
                    unreachable;
                },
            }
        },
        else => return state.failArgumentType("string.gsub", 3, "string/function/table", replacement),
    };
}

fn isFunctionValue(value: Value) bool {
    return std.mem.eql(u8, luaTypeName(value), "function");
}

fn invalidReplacementValue(state: *State, value: Value) ![]const u8 {
    var message = std.ArrayList(u8).empty;
    defer message.deinit(state.allocator);
    try runtime.appendFmt(state.allocator, &message, "invalid replacement value (a {s})", .{luaTypeName(value)});
    return state.failLibrary(try state.strings.intern(message.items));
}

fn luaTypeName(value: Value) []const u8 {
    return switch (value) {
        .nil => "nil",
        .boolean => "boolean",
        .integer, .number => "number",
        .string => "string",
        .table => "table",
        .userdata => "userdata",
        .closure, .api_callback, .coroutine_wrapper, .gmatch_iterator, .native_print, .native_tostring, .native_getmetatable, .native_setmetatable, .native_rawequal, .native_rawget, .native_rawset, .native_rawlen, .native_next, .native_pairs, .native_ipairs, .native_ipairs_iter, .native_table_create, .native_select, .native_assert, .native_pcall, .native_xpcall, .native_debug_traceback, .native_coroutine_create, .native_coroutine_resume, .native_coroutine_yield, .native_coroutine_status, .native_coroutine_running, .native_coroutine_isyieldable, .native_coroutine_close, .native_collectgarbage, .native_error, .native_coroutine_wrap, .native => "function",
        .thread => "thread",
    };
}

fn integerArgument(state: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !i64 {
    return state.argumentInteger(thread, op, function_name, index);
}

fn gsubStringReplacement(state: *State, replacement: []const u8, source: []const u8, matched: Match) ![]const u8 {
    if (std.mem.indexOfScalar(u8, replacement, '%') == null) return replacement;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    var index: usize = 0;
    while (index < replacement.len) : (index += 1) {
        if (replacement[index] != '%' or index + 1 >= replacement.len) {
            try out.append(state.allocator, replacement[index]);
            continue;
        }
        index += 1;
        switch (replacement[index]) {
            '0' => try out.appendSlice(state.allocator, source[matched.range.start..matched.range.end]),
            '1'...'9' => |capture_index| try appendReplacementCapture(state, &out, source, matched, capture_index - '0'),
            '%' => try out.append(state.allocator, '%'),
            else => return state.failLibrary("invalid use of '%' in replacement string"),
        }
    }
    return state.strings.intern(out.items);
}

fn appendReplacementCapture(state: *State, out: *std.ArrayList(u8), source: []const u8, matched: Match, one_based: u8) !void {
    if (matched.captures.count == 0 and one_based == 1) {
        try out.appendSlice(state.allocator, source[matched.range.start..matched.range.end]);
        return;
    }
    const index: usize = one_based - 1;
    if (index >= matched.captures.count) {
        try pattern_mod.invalidCaptureIndex(state, one_based);
        unreachable;
    }
    switch (matched.captures.slots[index]) {
        .range => |range| try out.appendSlice(state.allocator, source[range.start..range.end]),
        .position => |position| try runtime.appendFmt(state.allocator, out, "{d}", .{position + 1}),
        .unfinished => {
            try pattern_mod.invalidCaptureIndex(state, one_based);
            unreachable;
        },
    }
}

pub fn len(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "string.len", 0);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = @intCast(source.len) }});
}

pub fn lower(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try asciiMap(state, thread, op, true);
}

pub fn match(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try findImpl(state, thread, op, false);
}

pub fn rep(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "string.rep", 0);
    const count = try integerArgument(state, thread, op, "string.rep", 1);
    const sep = try state.optionalArgumentString(thread, op, "string.rep", 2) orelse "";
    if (count > 0 and repeatedLengthTooLarge(source.len, sep.len, @intCast(count))) return state.failLibrary("resulting string too large");
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    if (count > 0) {
        var index: i64 = 0;
        while (index < count) : (index += 1) {
            if (index & 0xfff == 0) try state.budget.checkInterrupt();
            if (index != 0) try out.appendSlice(state.allocator, sep);
            try out.appendSlice(state.allocator, source);
        }
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try internShortString(state, out.items) }});
}

fn internShortString(state: *State, bytes: []const u8) ![]const u8 {
    return if (bytes.len <= 40) try state.strings.intern(bytes) else try state.strings.allocate(bytes);
}

fn repeatedLengthTooLarge(source_len: usize, sep_len: usize, count: usize) bool {
    const max_string_len = std.math.maxInt(i32);
    var total = std.math.mul(usize, source_len, count) catch return true;
    if (count > 1) total = std.math.add(usize, total, std.math.mul(usize, sep_len, count - 1) catch return true) catch return true;
    return total > max_string_len;
}

pub fn reverse(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "string.reverse", 0);
    var out = try state.allocator.alloc(u8, source.len);
    defer state.allocator.free(out);
    for (source, 0..) |source_byte, index| out[source.len - 1 - index] = source_byte;
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(out) }});
}

/// Like `split`, but splits from the right.
pub fn rsplit(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try splitImpl(state, thread, op, true);
}

/// Splits on the separator, or ASCII whitespace when omitted, up to an optional maximum count.
pub fn split(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try splitImpl(state, thread, op, false);
}

fn splitImpl(state: *State, thread: *Thread, op: bytecode.Call, from_right: bool) !void {
    const function_name = if (from_right) "string.rsplit" else "string.split";
    const source = try state.expectArgumentString(thread, op, function_name, 0);
    const separator: ?[]const u8 = if (op.arg_count < 2 or runtime.argValue(state, thread, op, 1) == .nil)
        null
    else
        try state.expectArgumentString(thread, op, function_name, 1);
    const maxsplit = if (op.arg_count >= 3 and runtime.argValue(state, thread, op, 2) != .nil) try integerArgument(state, thread, op, function_name, 2) else -1;
    if (separator) |bytes| if (bytes.len == 0) return state.failArgumentMessage(function_name, 2, "empty separator");

    var pieces = std.ArrayList([]const u8).empty;
    defer pieces.deinit(state.allocator);
    if (separator) |bytes| {
        try splitOnSeparator(state, &pieces, source, bytes, maxsplit, from_right);
    } else {
        try splitWhitespace(state, &pieces, source, maxsplit, from_right);
    }

    const result = try state.newTableWithHints(@intCast(pieces.items.len), 0);
    for (pieces.items, 0..) |piece, index| {
        const output_index = if (from_right) pieces.items.len - index else index + 1;
        try state.setTableRaw(result.table, .{ .integer = @intCast(output_index) }, .{ .string = try state.strings.intern(piece) });
    }
    try state.returnValues(thread, op.base, op.return_count, &.{result});
}

fn splitOnSeparator(state: *State, pieces: *std.ArrayList([]const u8), source: []const u8, separator: []const u8, maxsplit: i64, from_right: bool) !void {
    var split_count: i64 = 0;
    if (!from_right) {
        var start: usize = 0;
        while (maxsplit < 0 or split_count < maxsplit) {
            const relative = std.mem.indexOf(u8, source[start..], separator) orelse break;
            const found = start + relative;
            try pieces.append(state.allocator, source[start..found]);
            start = found + separator.len;
            split_count += 1;
        }
        try pieces.append(state.allocator, source[start..]);
        return;
    }

    var end = source.len;
    while (maxsplit < 0 or split_count < maxsplit) {
        const found = std.mem.lastIndexOf(u8, source[0..end], separator) orelse break;
        try pieces.append(state.allocator, source[found + separator.len .. end]);
        end = found;
        split_count += 1;
    }
    try pieces.append(state.allocator, source[0..end]);
}

fn splitWhitespace(state: *State, pieces: *std.ArrayList([]const u8), source: []const u8, maxsplit: i64, from_right: bool) !void {
    if (from_right) return splitWhitespaceFromRight(state, pieces, source, maxsplit);

    var pos: usize = 0;
    while (pos < source.len and stripByte(null, source[pos])) pos += 1;
    if (pos == source.len) return;
    if (maxsplit == 0) return pieces.append(state.allocator, source[pos..]);

    var split_count: i64 = 0;
    while (pos < source.len) {
        const token_start = pos;
        while (pos < source.len and !stripByte(null, source[pos])) pos += 1;
        if (pos == source.len) return pieces.append(state.allocator, source[token_start..]);
        try pieces.append(state.allocator, source[token_start..pos]);
        split_count += 1;
        while (pos < source.len and stripByte(null, source[pos])) pos += 1;
        if (pos == source.len) return;
        if (maxsplit > 0 and split_count >= maxsplit) return pieces.append(state.allocator, source[pos..]);
    }
}

fn splitWhitespaceFromRight(state: *State, pieces: *std.ArrayList([]const u8), source: []const u8, maxsplit: i64) !void {
    var end = source.len;
    while (end > 0 and stripByte(null, source[end - 1])) end -= 1;
    if (end == 0) return;
    if (maxsplit == 0) return pieces.append(state.allocator, source[0..end]);

    var split_count: i64 = 0;
    while (end > 0) {
        const token_end = end;
        var start = end;
        while (start > 0 and !stripByte(null, source[start - 1])) start -= 1;
        if (start == 0) return pieces.append(state.allocator, source[0..token_end]);
        try pieces.append(state.allocator, source[start..token_end]);
        split_count += 1;
        end = start;
        while (end > 0 and stripByte(null, source[end - 1])) end -= 1;
        if (end == 0) return;
        if (maxsplit > 0 and split_count >= maxsplit) return pieces.append(state.allocator, source[0..end]);
    }
}

/// Trims ASCII whitespace, or bytes in the optional character set.
pub fn strip(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "string.strip", 0);
    const chars: ?[]const u8 = if (op.arg_count < 2 or runtime.argValue(state, thread, op, 1) == .nil)
        null
    else
        try state.expectArgumentString(thread, op, "string.strip", 1);

    var start: usize = 0;
    while (start < source.len and stripByte(chars, source[start])) : (start += 1) {}
    var end = source.len;
    while (end > start and stripByte(chars, source[end - 1])) : (end -= 1) {}

    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(source[start..end]) }});
}

fn stripByte(chars: ?[]const u8, byte_value: u8) bool {
    const bytes = chars orelse " \t\n\r\x0b\x0c";
    return std.mem.indexOfScalar(u8, bytes, byte_value) != null;
}

pub fn sub(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "string.sub", 0);
    const start_arg = try integerArgument(state, thread, op, "string.sub", 1);
    const stop_arg = try state.optionalArgumentInteger(thread, op, "string.sub", 2, -1);
    const start = normalizeIndex(start_arg, source.len);
    const stop = normalizeIndex(stop_arg, source.len);
    if (start > stop or start > source.len) {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern("") }});
        return;
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(source[@max(start, 1) - 1 .. @min(stop, source.len)]) }});
}

pub fn upper(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try asciiMap(state, thread, op, false);
}

fn asciiMap(state: *State, thread: *Thread, op: bytecode.Call, to_lower: bool) !void {
    const source = try state.expectArgumentString(thread, op, if (to_lower) "string.lower" else "string.upper", 0);
    var out = try state.allocator.alloc(u8, source.len);
    defer state.allocator.free(out);
    for (source, 0..) |source_byte, index| out[index] = if (to_lower) std.ascii.toLower(source_byte) else std.ascii.toUpper(source_byte);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(out) }});
}

fn findImpl(state: *State, thread: *Thread, op: bytecode.Call, positions: bool) !void {
    const function_name = if (positions) "string.find" else "string.match";
    const source = try state.expectArgumentString(thread, op, function_name, 0);
    const pattern = try state.expectArgumentString(thread, op, function_name, 1);
    const initial = normalizeIndex(try state.optionalArgumentInteger(thread, op, function_name, 2, 1), source.len);
    const plain = if (positions)
        runtime.truthy(runtime.argValue(state, thread, op, 3)) or !pattern_mod.patternHasSpecials(pattern)
    else
        !pattern_mod.patternHasMagic(pattern);
    if (pattern.len == 0 and initial > source.len + 1) {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
        return;
    }
    const start = if (initial <= 1) 0 else @min(initial - 1, source.len);
    const found = if (plain) pattern_mod.plainFind(source, pattern, start) else try pattern_mod.simplePatternFind(state, source, pattern, start);
    if (found) |range| {
        if (positions) {
            if (range.captures.count == 0) {
                const values = [_]Value{
                    .{ .integer = @intCast(range.range.start + 1) },
                    .{ .integer = @intCast(range.range.end) },
                };
                try state.returnValues(thread, op.base, op.return_count, values[0..]);
                return;
            }
            var values = std.ArrayList(Value).empty;
            defer values.deinit(state.allocator);
            try values.append(state.allocator, .{ .integer = @intCast(range.range.start + 1) });
            try values.append(state.allocator, .{ .integer = @intCast(range.range.end) });
            try pattern_mod.appendCaptureValues(state, &values, source, range.captures);
            try state.returnValues(thread, op.base, op.return_count, values.items);
        } else {
            if (range.captures.count == 0) {
                try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(source[range.range.start..range.range.end]) }});
                return;
            }
            var values = std.ArrayList(Value).empty;
            defer values.deinit(state.allocator);
            try pattern_mod.appendMatchValues(state, &values, source, range);
            try state.returnValues(thread, op.base, op.return_count, values.items);
        }
    } else {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
    }
}

fn normalizeIndex(index: i64, source_len: usize) usize {
    const length: i64 = @intCast(source_len);
    const normalized = if (index < 0) length + index + 1 else index;
    if (normalized <= 0) return 0;
    return @intCast(normalized);
}
