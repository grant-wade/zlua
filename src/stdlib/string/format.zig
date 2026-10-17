const std = @import("std");
const compile = @import("../../compile.zig");
const runtime = @import("../../runtime.zig");
const metatable_mod = @import("../../runtime/metatable.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;

pub fn format(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const function_name = "string.format";
    const fmt = try state.expectArgumentString(thread, op, function_name, 0);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    var arg: u32 = 0;
    var index: usize = 0;
    while (index < fmt.len) {
        if (fmt[index] != '%') {
            try out.append(state.allocator, fmt[index]);
            index += 1;
            continue;
        }
        index += 1;
        if (index < fmt.len and fmt[index] == '%') {
            try out.append(state.allocator, '%');
            index += 1;
            continue;
        }
        arg += 1;
        if (arg >= op.arg_count) return state.failArgumentMessage(function_name, arg + 1, "no value");

        var span: usize = 0;
        while (index + span < fmt.len and std.mem.indexOfScalar(u8, "-+#0 123456789.", fmt[index + span]) != null) span += 1;
        if (span + 1 >= max_format - 10) return state.failLibrary("invalid format (too long)");
        const conversion: u8 = if (index + span < fmt.len) fmt[index + span] else 0;
        const end = if (conversion == 0) index + span else index + span + 1;
        const form = fmt[index - 1 .. end];
        index = end;

        const value = runtime.argValue(state, thread, op, arg);
        switch (conversion) {
            'c' => {
                try checkFormat(state, form, "-", false);
                const integer = try state.argumentInteger(thread, op, function_name, arg);
                const byte_value: [1]u8 = .{@truncate(@as(u64, @bitCast(integer)))};
                try appendPadded(state.allocator, &out, &byte_value, parseFormatSpec(form), ' ');
            },
            'd', 'i', 'u', 'o', 'x', 'X' => {
                const integer = try state.argumentInteger(thread, op, function_name, arg);
                const flags = switch (conversion) {
                    'd', 'i' => "-+0 ",
                    'u' => "-0",
                    else => "-#0",
                };
                try checkFormat(state, form, flags, true);
                try appendIntegerFormat(state, &out, integer, parseFormatSpec(form));
            },
            'a', 'A' => {
                try checkFormat(state, form, "-+#0 ", true);
                const number = try state.argumentNumber(thread, op, function_name, arg);
                try appendFloatFormat(state, &out, number, parseFormatSpec(form));
            },
            'e', 'E', 'f', 'g', 'G' => {
                const number = try state.argumentNumber(thread, op, function_name, arg);
                try checkFormat(state, form, "-+#0 ", true);
                try appendFloatFormat(state, &out, number, parseFormatSpec(form));
            },
            'p' => {
                try checkFormat(state, form, "-", false);
                try appendPointer(state, &out, value, parseFormatSpec(form));
            },
            'q' => {
                if (form.len > 2) return state.failLibrary("specifier '%q' cannot have modifiers");
                try appendLiteral(state, &out, value, arg);
            },
            's' => {
                const text = try metatable_mod.valueToString(state, thread, value);
                if (form.len == 2) {
                    try out.appendSlice(state.allocator, text);
                } else {
                    if (std.mem.indexOfScalar(u8, text, 0) != null) return state.failArgumentMessage(function_name, arg + 1, "string contains zeros");
                    try checkFormat(state, form, "-", true);
                    const spec = parseFormatSpec(form);
                    if (spec.precision == null and text.len >= 100) {
                        try out.appendSlice(state.allocator, text);
                    } else {
                        const precision = spec.precision orelse text.len;
                        try appendPadded(state.allocator, &out, text[0..@min(precision, text.len)], spec, ' ');
                    }
                }
            },
            else => return state.failLibraryFmt("invalid conversion '{s}' to 'format'", .{form}),
        }
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(out.items) }});
}

const max_format = 32;

fn checkFormat(state: *State, form: []const u8, flags: []const u8, allow_precision: bool) !void {
    var index: usize = 1;
    while (index < form.len and std.mem.indexOfScalar(u8, flags, form[index]) != null) index += 1;
    if (index < form.len and form[index] != '0') {
        index = skipTwoDigits(form, index);
        if (index < form.len and form[index] == '.' and allow_precision) index = skipTwoDigits(form, index + 1);
    }
    if (index >= form.len or !std.ascii.isAlphabetic(form[index])) {
        return state.failLibraryFmt("invalid conversion specification: '{s}'", .{form});
    }
}

fn skipTwoDigits(form: []const u8, start: usize) usize {
    var index = start;
    if (index < form.len and std.ascii.isDigit(form[index])) {
        index += 1;
        if (index < form.len and std.ascii.isDigit(form[index])) index += 1;
    }
    return index;
}

const FormatSpec = runtime.number_format.Spec;

fn parseFormatSpec(form: []const u8) FormatSpec {
    var spec: FormatSpec = .{ .conversion = form[form.len - 1] };
    var index: usize = 1;
    while (index < form.len) : (index += 1) switch (form[index]) {
        '-' => spec.left_align = true,
        '+' => spec.force_sign = true,
        ' ' => spec.space_sign = true,
        '#' => spec.alternate = true,
        '0' => spec.zero_pad = true,
        else => break,
    };
    while (index < form.len and std.ascii.isDigit(form[index])) : (index += 1) spec.width = spec.width * 10 + form[index] - '0';
    if (index < form.len and form[index] == '.') {
        index += 1;
        var precision: usize = 0;
        while (index < form.len and std.ascii.isDigit(form[index])) : (index += 1) precision = precision * 10 + form[index] - '0';
        spec.precision = precision;
    }
    return spec;
}

fn appendFloatFormat(state: *State, out: *std.ArrayList(u8), number: f64, spec: FormatSpec) !void {
    var buffer: [runtime.number_format.max_formatted_len]u8 = undefined;
    try out.appendSlice(state.allocator, runtime.number_format.formatFloat(&buffer, spec, number));
}

fn appendIntegerFormat(state: *State, out: *std.ArrayList(u8), integer: i64, spec: FormatSpec) !void {
    var digits = std.ArrayList(u8).empty;
    defer digits.deinit(state.allocator);

    const signed = spec.conversion == 'd' or spec.conversion == 'i';
    const negative = signed and integer < 0;
    const unsigned: u64 = if (signed)
        if (negative) 0 -% @as(u64, @bitCast(integer)) else @intCast(integer)
    else
        @bitCast(integer);

    if (!(spec.precision == 0 and unsigned == 0)) switch (spec.conversion) {
        'd', 'i', 'u' => try runtime.appendFmt(state.allocator, &digits, "{d}", .{unsigned}),
        'x' => try runtime.appendFmt(state.allocator, &digits, "{x}", .{unsigned}),
        'X' => try runtime.appendFmt(state.allocator, &digits, "{X}", .{unsigned}),
        'o' => try runtime.appendFmt(state.allocator, &digits, "{o}", .{unsigned}),
        else => unreachable,
    };

    var prefix = std.ArrayList(u8).empty;
    defer prefix.deinit(state.allocator);
    if (negative) {
        try prefix.append(state.allocator, '-');
    } else if (signed and spec.force_sign) {
        try prefix.append(state.allocator, '+');
    } else if (signed and spec.space_sign) {
        try prefix.append(state.allocator, ' ');
    }
    if (spec.alternate) switch (spec.conversion) {
        'x' => if (unsigned != 0) try prefix.appendSlice(state.allocator, "0x"),
        'X' => if (unsigned != 0) try prefix.appendSlice(state.allocator, "0X"),
        'o' => if (digits.items.len == 0 or digits.items[0] != '0') {
            if (spec.precision == null or spec.precision.? <= digits.items.len) try prefix.append(state.allocator, '0');
        },
        else => {},
    };

    const precision_zeroes = if (spec.precision) |precision| if (precision > digits.items.len) precision - digits.items.len else 0 else 0;
    const unpadded_len = prefix.items.len + precision_zeroes + digits.items.len;
    const width_padding = if (spec.width > unpadded_len) spec.width - unpadded_len else 0;
    const zero_width_padding = spec.zero_pad and spec.precision == null and !spec.left_align;

    if (!spec.left_align and !zero_width_padding) try out.appendNTimes(state.allocator, ' ', width_padding);
    try out.appendSlice(state.allocator, prefix.items);
    if (zero_width_padding) try out.appendNTimes(state.allocator, '0', width_padding);
    try out.appendNTimes(state.allocator, '0', precision_zeroes);
    try out.appendSlice(state.allocator, digits.items);
    if (spec.left_align) try out.appendNTimes(state.allocator, ' ', width_padding);
}

fn appendLiteral(state: *State, out: *std.ArrayList(u8), value: Value, arg: u32) !void {
    switch (value) {
        .string => |string| try appendQuoted(state.allocator, out, string),
        .integer => |integer| if (integer == std.math.minInt(i64))
            try runtime.appendFmt(state.allocator, out, "0x{x}", .{@as(u64, @bitCast(integer))})
        else
            try runtime.appendFmt(state.allocator, out, "{d}", .{integer}),
        .number => |number| {
            if (std.math.isNan(number)) {
                try out.appendSlice(state.allocator, "(0/0)");
            } else if (number == std.math.inf(f64)) {
                try out.appendSlice(state.allocator, "1e9999");
            } else if (number == -std.math.inf(f64)) {
                try out.appendSlice(state.allocator, "-1e9999");
            } else {
                try appendFloatFormat(state, out, number, .{ .conversion = 'a' });
            }
        },
        .nil, .boolean => try runtime.appendValue(state.allocator, out, value),
        else => return state.failArgumentMessage("string.format", arg + 1, "value has no literal form"),
    }
}

fn appendQuoted(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source: []const u8) !void {
    try out.append(allocator, '"');
    for (source, 0..) |source_byte, index| {
        if (source_byte == '"' or source_byte == '\\' or source_byte == '\n') {
            try out.append(allocator, '\\');
            try out.append(allocator, source_byte);
        } else if (std.ascii.isControl(source_byte)) {
            const next_is_digit = index + 1 < source.len and std.ascii.isDigit(source[index + 1]);
            if (next_is_digit) {
                try runtime.appendFmt(allocator, out, "\\{d:0>3}", .{source_byte});
            } else {
                try runtime.appendFmt(allocator, out, "\\{d}", .{source_byte});
            }
        } else {
            try out.append(allocator, source_byte);
        }
    }
    try out.append(allocator, '"');
}

fn appendPointer(state: *State, out: *std.ArrayList(u8), value: Value, spec: FormatSpec) !void {
    var raw = std.ArrayList(u8).empty;
    defer raw.deinit(state.allocator);
    if (pointerAddress(value)) |address| {
        try runtime.appendFmt(state.allocator, &raw, "0x{x}", .{address});
    } else {
        try raw.appendSlice(state.allocator, "(null)");
    }
    try appendPadded(state.allocator, out, raw.items, spec, ' ');
}

fn pointerAddress(value: Value) ?usize {
    return switch (value) {
        .string => |string| @intFromPtr(string.ptr),
        .table => |table| @intFromPtr(table),
        .userdata => |userdata| @intFromPtr(userdata),
        .closure => |closure| @intFromPtr(closure),
        .thread => |thread| @intFromPtr(thread),
        .coroutine_wrapper => |thread| @intFromPtr(thread),
        .gmatch_iterator => |table| @intFromPtr(table),
        .native_print, .native_tostring, .native_getmetatable, .native_setmetatable, .native_rawequal, .native_rawget, .native_rawset, .native_rawlen, .native_next, .native_pairs, .native_ipairs, .native_ipairs_iter, .native_table_create, .native_select, .native_assert, .native_error, .native_pcall, .native_xpcall, .native_collectgarbage, .native_debug_traceback, .native_coroutine_create, .native_coroutine_resume, .native_coroutine_yield, .native_coroutine_status, .native_coroutine_running, .native_coroutine_isyieldable, .native_coroutine_close, .native_coroutine_wrap => @as(usize, 0x1000) + @as(usize, @intFromEnum(std.meta.activeTag(value))),
        .native => |native| @as(usize, 0x2000) + @as(usize, @intFromEnum(native)),
        .api_callback => |id| @as(usize, 0x3000) + id,
        else => null,
    };
}

fn appendPadded(allocator: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8, spec: FormatSpec, pad: u8) !void {
    const padding = if (spec.width > text.len) spec.width - text.len else 0;
    if (!spec.left_align) try out.appendNTimes(allocator, pad, padding);
    try out.appendSlice(allocator, text);
    if (spec.left_align) try out.appendNTimes(allocator, pad, padding);
}
