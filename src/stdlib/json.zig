const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const data = @import("data.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Table = runtime.Table;

pub fn nullValue(state: *State) !Value {
    return data.nullValue(state);
}

pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const input = try data.inputBytes(state, runtime.argValue(state, thread, op, 0), "json.read");
    var reader: Reader = .{ .state = state, .input = input, .builder = .init(state) };
    defer reader.deinit();
    try data.returnValue(state, thread, op, try reader.document());
}

const Reader = struct {
    state: *State,
    input: []const u8,
    pos: usize = 0,
    builder: data.Builder,
    scratch: std.ArrayList(u8) = .empty,

    fn deinit(self: *Reader) void {
        self.builder.deinit();
        self.scratch.deinit(self.state.allocator);
    }

    fn fail(self: *Reader, offset: usize, comptime fmt: []const u8, args: anytype) runtime.RuntimeError {
        return data.failAtLine(self.state, "json.read", self.input, offset, fmt, args);
    }

    fn document(self: *Reader) !Value {
        const b = &self.builder;
        value: while (true) {
            self.skipWhitespace();
            const start = self.pos;
            const byte = self.peek() orelse return self.fail(start, "expected a value, found end of input", .{});
            switch (byte) {
                '{', '[' => {
                    if (b.depth() == data.max_depth) return self.fail(start, "nesting deeper than {d} levels", .{data.max_depth});
                    self.pos += 1;
                    const close: u8 = if (byte == '{') '}' else ']';
                    try b.begin(if (byte == '{') .object else .array, 0);
                    self.skipWhitespace();
                    if (self.peek() == close) {
                        self.pos += 1;
                        try b.end();
                    } else {
                        if (byte == '{') try self.key();
                        continue :value;
                    }
                },
                '"' => try b.appendString(try self.string()),
                '-', '0'...'9' => try b.append(try self.number()),
                't' => try self.literal("true", .{ .boolean = true }),
                'f' => try self.literal("false", .{ .boolean = false }),
                'n' => try self.literal("null", try data.nullValue(self.state)),
                else => return self.fail(start, "expected a value, found {f}", .{data.ByteText{ .byte = byte }}),
            }

            while (b.depth() != 0) {
                self.skipWhitespace();
                const frame = b.top();
                const close: u8 = if (frame.kind == .object) '}' else ']';
                const next = self.peek() orelse return self.fail(self.pos, "expected ',' or '{c}', found end of input", .{close});
                if (next == ',') {
                    self.pos += 1;
                    if (frame.kind == .object) try self.key();
                    continue :value;
                }
                if (next != close) return self.fail(self.pos, "expected ',' or '{c}', found {f}", .{ close, data.ByteText{ .byte = next } });
                self.pos += 1;
                try b.end();
            }

            self.skipWhitespace();
            if (self.pos != self.input.len) return self.fail(self.pos, "unexpected {f} after the document", .{data.ByteText{ .byte = self.input[self.pos] }});
            return b.root;
        }
    }

    fn key(self: *Reader) !void {
        self.skipWhitespace();
        const next = self.peek() orelse return self.fail(self.pos, "expected an object key, found end of input", .{});
        if (next != '"') return self.fail(self.pos, "expected a string object key, found {f}", .{data.ByteText{ .byte = next }});
        try self.builder.setKey(try self.string());
        self.skipWhitespace();
        const colon = self.peek() orelse return self.fail(self.pos, "expected ':' after object key, found end of input", .{});
        if (colon != ':') return self.fail(self.pos, "expected ':' after object key, found {f}", .{data.ByteText{ .byte = colon }});
        self.pos += 1;
    }

    fn peek(self: *const Reader) ?u8 {
        return if (self.pos < self.input.len) self.input[self.pos] else null;
    }

    fn skipWhitespace(self: *Reader) void {
        while (self.pos < self.input.len) : (self.pos += 1) {
            switch (self.input[self.pos]) {
                ' ', '\t', '\n', '\r' => {},
                else => return,
            }
        }
    }

    fn literal(self: *Reader, comptime text: []const u8, value: Value) !void {
        if (!std.mem.startsWith(u8, self.input[self.pos..], text)) return self.fail(self.pos, "invalid literal, expected '{s}'", .{text});
        self.pos += text.len;
        try self.builder.append(value);
    }

    fn number(self: *Reader) !Value {
        const start = self.pos;
        var is_float = false;
        if (self.peek() == '-') self.pos += 1;
        if (self.peek() == '0') {
            self.pos += 1;
            if (self.peek()) |next| if (std.ascii.isDigit(next)) return self.fail(start, "leading zeros are not allowed", .{});
        } else if (self.digits() == 0) {
            return self.fail(start, "invalid number", .{});
        }
        if (self.peek() == '.') {
            self.pos += 1;
            is_float = true;
            if (self.digits() == 0) return self.fail(self.pos, "expected a digit after the decimal point", .{});
        }
        if (self.peek() == 'e' or self.peek() == 'E') {
            self.pos += 1;
            is_float = true;
            if (self.peek() == '+' or self.peek() == '-') self.pos += 1;
            if (self.digits() == 0) return self.fail(self.pos, "expected a digit in the exponent", .{});
        }

        const text = self.input[start..self.pos];
        if (is_float) return .{ .number = std.fmt.parseFloat(f64, text) catch return self.fail(start, "invalid number", .{}) };
        return .{ .integer = std.fmt.parseInt(i64, text, 10) catch return self.fail(start, "integer {s} is outside the 64-bit range", .{text}) };
    }

    fn digits(self: *Reader) usize {
        const start = self.pos;
        while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) self.pos += 1;
        return self.pos - start;
    }

    /// Reads a string starting at its opening quote. The result is valid until the next call.
    fn string(self: *Reader) ![]const u8 {
        const start = self.pos;
        self.pos += 1;
        const run_start = self.pos;
        while (self.pos < self.input.len) {
            const byte = self.input[self.pos];
            if (byte == '"') {
                const bytes = self.input[run_start..self.pos];
                self.pos += 1;
                if (!std.unicode.utf8ValidateSlice(bytes)) return self.fail(start, "string is not valid UTF-8", .{});
                return bytes;
            }
            if (byte == '\\') break;
            if (byte < 0x20) return self.fail(self.pos, "control character in string", .{});
            self.pos += 1;
        }

        self.scratch.clearRetainingCapacity();
        const allocator = self.state.allocator;
        try self.scratch.appendSlice(allocator, self.input[run_start..self.pos]);
        while (true) {
            const byte = self.peek() orelse return self.fail(start, "unterminated string", .{});
            switch (byte) {
                '"' => {
                    self.pos += 1;
                    if (!std.unicode.utf8ValidateSlice(self.scratch.items)) return self.fail(start, "string is not valid UTF-8", .{});
                    return self.scratch.items;
                },
                '\\' => {
                    const escape_start = self.pos;
                    self.pos += 1;
                    const kind = self.peek() orelse return self.fail(start, "unterminated string", .{});
                    self.pos += 1;
                    const decoded: u8 = switch (kind) {
                        '"' => '"',
                        '\\' => '\\',
                        '/' => '/',
                        'b' => 0x08,
                        'f' => 0x0c,
                        'n' => '\n',
                        'r' => '\r',
                        't' => '\t',
                        'u' => {
                            try self.unicodeEscape(escape_start);
                            continue;
                        },
                        else => return self.fail(escape_start, "invalid escape '\\{c}'", .{kind}),
                    };
                    try self.scratch.append(allocator, decoded);
                },
                0...0x1f => return self.fail(self.pos, "control character in string", .{}),
                else => {
                    try self.scratch.append(allocator, byte);
                    self.pos += 1;
                },
            }
        }
    }

    fn unicodeEscape(self: *Reader, escape_start: usize) !void {
        var codepoint: u21 = try self.hex4(escape_start);
        if (codepoint >= 0xdc00 and codepoint <= 0xdfff) return self.fail(escape_start, "unpaired surrogate in \\u escape", .{});
        if (codepoint >= 0xd800 and codepoint <= 0xdbff) {
            if (!std.mem.startsWith(u8, self.input[self.pos..], "\\u")) return self.fail(escape_start, "unpaired surrogate in \\u escape", .{});
            self.pos += 2;
            const low = try self.hex4(escape_start);
            if (low < 0xdc00 or low > 0xdfff) return self.fail(escape_start, "unpaired surrogate in \\u escape", .{});
            codepoint = 0x10000 + ((codepoint - 0xd800) << 10) + (low - 0xdc00);
        }
        var buffer: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buffer) catch unreachable;
        try self.scratch.appendSlice(self.state.allocator, buffer[0..len]);
    }

    fn hex4(self: *Reader, escape_start: usize) !u21 {
        if (self.input.len - self.pos < 4) return self.fail(escape_start, "\\u escape needs four hex digits", .{});
        const value = std.fmt.parseInt(u16, self.input[self.pos..][0..4], 16) catch return self.fail(escape_start, "\\u escape needs four hex digits", .{});
        self.pos += 4;
        return value;
    }
};

pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0) return state.failArgumentMessage("json.write", 1, "value expected");
    var writer: Writer = .{ .walker = .init(state, "json.write"), .value = runtime.argValue(state, thread, op, 0) };
    try writer.readOptions(state, thread, op);
    try data.returnEncoded(state, thread, op, "json.write", &writer, Writer.encode);
}

const Writer = struct {
    walker: data.Walker,
    value: Value,
    pretty: bool = false,
    indent: usize = 2,

    fn readOptions(self: *Writer, state: *State, thread: *Thread, op: bytecode.Call) !void {
        const table = try data.optionsTable(state, thread, op, "json.write") orelse return;
        if (try data.boolOption(state, table, "json.write", "pretty")) |pretty| self.pretty = pretty;
        const indent = table.getLiteral("indent");
        if (indent != .nil) {
            state.budget.noteLongString(indent);
            const integer = runtime.toInteger(indent) orelse return state.failArgumentType("json.write", 2, "table with numeric indent", indent);
            if (integer < 0) return state.failArgumentMessage("json.write", 2, "indent out of range");
            self.indent = std.math.cast(usize, integer) orelse return state.failArgumentMessage("json.write", 2, "indent out of range");
        }
    }

    fn encode(self: *Writer, out: *std.Io.Writer) !void {
        try self.writeValue(out, self.value);
    }

    fn writeValue(self: *Writer, out: *std.Io.Writer, value: Value) anyerror!void {
        try self.walker.visit(value);
        switch (value) {
            .nil => try out.writeAll("null"),
            .boolean => |boolean| try out.writeAll(if (boolean) "true" else "false"),
            .integer => |integer| try out.print("{d}", .{integer}),
            .number => |number| {
                if (!std.math.isFinite(number)) return self.walker.fail("non-finite number", .{});
                try data.writeFloat(out, number);
            },
            .string => |string| try self.writeString(out, string.bytes()),
            .table => |table| try self.writeTable(out, table),
            else => return self.walker.failValue(value),
        }
    }

    fn writeTable(self: *Writer, out: *std.Io.Writer, table: *Table) anyerror!void {
        switch (try self.walker.enter(table)) {
            .null => try out.writeAll("null"),
            .datetime => |value| {
                var buffer: [64]u8 = undefined;
                try self.writeString(out, std.fmt.bufPrint(&buffer, "{f}", .{value}) catch unreachable);
            },
            .extension => return self.walker.fail("cannot encode a MessagePack extension", .{}),
            .array => |len| {
                defer self.walker.leave();
                try out.writeByte('[');
                for (1..len + 1) |index| {
                    if (index != 1) try out.writeByte(',');
                    try self.newline(out, self.walker.depth);
                    self.walker.step(.{ .index = index });
                    try self.writeValue(out, table.get(.{ .integer = @intCast(index) }));
                }
                if (len != 0) try self.newline(out, self.walker.depth - 1);
                try out.writeByte(']');
            },
            .object => |count| {
                defer self.walker.leave();
                try out.writeByte('{');
                var written: usize = 0;
                for (table.entries()) |entry| {
                    if (entry.value == .nil) continue;
                    const name = entry.key.string.bytes();
                    self.walker.step(.{ .key = name });
                    if (written != 0) try out.writeByte(',');
                    try self.newline(out, self.walker.depth);
                    try self.writeString(out, name);
                    try out.writeAll(if (self.pretty) ": " else ":");
                    try self.writeValue(out, entry.value);
                    written += 1;
                }
                if (count != 0) try self.newline(out, self.walker.depth - 1);
                try out.writeByte('}');
            },
        }
    }

    fn newline(self: *Writer, out: *std.Io.Writer, depth: usize) !void {
        if (!self.pretty) return;
        try out.writeByte('\n');
        try out.splatByteAll(' ', depth *| self.indent);
    }

    fn writeString(self: *Writer, out: *std.Io.Writer, bytes: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(bytes)) return self.walker.fail("string is not valid UTF-8", .{});
        try out.writeByte('"');
        var run_start: usize = 0;
        for (bytes, 0..) |byte, index| {
            const escaped: []const u8 = switch (byte) {
                '"' => "\\\"",
                '\\' => "\\\\",
                '\n' => "\\n",
                '\r' => "\\r",
                '\t' => "\\t",
                0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => {
                    try out.writeAll(bytes[run_start..index]);
                    try out.print("\\u{x:0>4}", .{byte});
                    run_start = index + 1;
                    continue;
                },
                else => continue,
            };
            try out.writeAll(bytes[run_start..index]);
            try out.writeAll(escaped);
            run_start = index + 1;
        }
        try out.writeAll(bytes[run_start..]);
        try out.writeByte('"');
    }
};
