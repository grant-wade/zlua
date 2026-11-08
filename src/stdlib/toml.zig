const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const data = @import("data.zig");
const datetime = @import("datetime.zig");
const metatable_mod = @import("../runtime/metatable.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Table = runtime.Table;
const String = @import("../runtime/types.zig").String;

pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const input = try data.inputBytes(state, runtime.argValue(state, thread, op, 0), "toml.read");
    var parser: Parser = .{ .state = state, .input = input };
    defer parser.deinit();
    try data.returnValue(state, thread, op, .{ .table = try parser.document() });
}

/// How a table or array was defined, which decides how later lines may extend it.
const Origin = enum {
    /// Created as a parent of a `[header]`; a later header may still define it.
    implicit,
    /// Defined by a `[header]` or as an element of an array of tables.
    header,
    /// Created by a dotted key.
    dotted,
    inline_table,
    static_array,
    table_array,
};

const Meta = struct {
    origin: Origin,
    /// Element count, for arrays of tables.
    len: i64 = 0,
};

const Key = struct {
    name: *const String,
    pos: usize,
};

/// Where the next value is stored: under `key` in `table`, or appended to `table` when `key` is null.
const Target = struct {
    table: *Table,
    key: ?*const String,
    /// Nesting depth of `table`, counting the root as 1.
    depth: usize,
};

const Frame = struct {
    kind: enum { array, inline_table },
    table: *Table,
    depth: usize,
    next_index: i64 = 1,
};

const Parser = struct {
    state: *State,
    input: []const u8,
    pos: usize = 0,
    meta: std.AutoHashMapUnmanaged(*Table, Meta) = .empty,
    keys: std.ArrayList(Key) = .empty,
    frames: std.ArrayList(Frame) = .empty,
    scratch: std.ArrayList(u8) = .empty,

    fn deinit(self: *Parser) void {
        const allocator = self.state.allocator;
        self.meta.deinit(allocator);
        self.keys.deinit(allocator);
        self.frames.deinit(allocator);
        self.scratch.deinit(allocator);
    }

    fn fail(self: *Parser, offset: usize, comptime fmt: []const u8, args: anytype) runtime.RuntimeError {
        return data.failAtLine(self.state, "toml.read", self.input, offset, fmt, args);
    }

    fn failFound(self: *Parser, comptime expected: []const u8) runtime.RuntimeError {
        if (self.pos == self.input.len) return self.fail(self.pos, expected ++ ", found end of input", .{});
        const byte = self.input[self.pos];
        if (byte == '\n' or byte == '\r') return self.fail(self.pos, expected ++ ", found a line break", .{});
        return self.fail(self.pos, expected ++ ", found {f}", .{data.ByteText{ .byte = byte }});
    }

    fn document(self: *Parser) !*Table {
        if (firstInvalidUtf8(self.input)) |offset| return self.fail(offset, "invalid UTF-8", .{});
        if (std.mem.startsWith(u8, self.input, "\xef\xbb\xbf")) self.pos = 3;
        try data.ensureSupportTables(self.state);

        const root = try self.newTable(.object, .header);
        var section = root;
        var section_depth: usize = 1;
        while (true) {
            self.skipSpace();
            const byte = self.peek() orelse break;
            switch (byte) {
                '#' => try self.comment(),
                '\n', '\r' => try self.newline(),
                '[' => {
                    section = try self.header(root);
                    section_depth = self.keys.items.len + 1;
                    try self.endOfLine();
                },
                else => {
                    const target = try self.keyTarget(section, section_depth);
                    try self.value(target);
                    try self.endOfLine();
                },
            }
        }
        return root;
    }

    fn header(self: *Parser, root: *Table) !*Table {
        self.pos += 1;
        const is_array = self.peek() == '[';
        if (is_array) self.pos += 1;
        self.skipSpace();
        try self.keyPath(1);
        self.skipSpace();
        if (is_array) {
            if (!std.mem.startsWith(u8, self.input[self.pos..], "]]")) return self.failFound("expected ']]' to close the array of tables header");
            self.pos += 2;
        } else {
            if (self.peek() != ']') return self.failFound("expected ']' to close the table header");
            self.pos += 1;
        }

        const keys = self.keys.items;
        var table = root;
        for (keys[0 .. keys.len - 1], 0..) |key, index| table = try self.descendHeader(table, key, index);

        const last = keys[keys.len - 1];
        const existing = table.get(.{ .string = last.name });
        if (is_array) {
            const array = switch (existing) {
                .nil => blk: {
                    const array = try self.newTable(.array, .table_array);
                    try self.set(table, last.name, .{ .table = array });
                    break :blk array;
                },
                .table => |existing_table| if (self.originOf(existing_table) == .table_array) existing_table else return self.fail(last.pos, "'{f}' is already defined and is not an array of tables", .{self.path(keys.len)}),
                else => return self.fail(last.pos, "'{f}' already has a value", .{self.path(keys.len)}),
            };
            const item = try self.newTable(.object, .header);
            const meta = self.meta.getPtr(array).?;
            meta.len += 1;
            try self.state.setTableRaw(array, .{ .integer = meta.len }, .{ .table = item });
            return item;
        }
        switch (existing) {
            .nil => {
                const created = try self.newTable(.object, .header);
                try self.set(table, last.name, .{ .table = created });
                return created;
            },
            .table => |existing_table| {
                const meta = self.meta.getPtr(existing_table).?;
                switch (meta.origin) {
                    .implicit => {
                        meta.origin = .header;
                        return existing_table;
                    },
                    .table_array => return self.fail(last.pos, "'{f}' is an array of tables; use [[{f}]] to add an element", .{ self.path(keys.len), self.path(keys.len) }),
                    .static_array => return self.fail(last.pos, "'{f}' already has a value", .{self.path(keys.len)}),
                    else => return self.fail(last.pos, "table '{f}' is already defined", .{self.path(keys.len)}),
                }
            },
            else => return self.fail(last.pos, "'{f}' already has a value", .{self.path(keys.len)}),
        }
    }

    /// Steps from `table` into the parent table `key` of a header, creating it if needed.
    fn descendHeader(self: *Parser, table: *Table, key: Key, index: usize) !*Table {
        switch (table.get(.{ .string = key.name })) {
            .nil => {
                const created = try self.newTable(.object, .implicit);
                try self.set(table, key.name, .{ .table = created });
                return created;
            },
            .table => |existing| {
                const meta = self.meta.get(existing).?;
                return switch (meta.origin) {
                    .implicit, .header, .dotted => existing,
                    .table_array => existing.get(.{ .integer = meta.len }).table,
                    .inline_table => self.fail(key.pos, "inline table '{f}' cannot be extended", .{self.path(index + 1)}),
                    .static_array => self.fail(key.pos, "'{f}' is an array, not a table", .{self.path(index + 1)}),
                };
            },
            else => return self.fail(key.pos, "'{f}' already has a value that is not a table", .{self.path(index + 1)}),
        }
    }

    /// Parses `key =` and resolves its dotted parts under `base`, which sits at `base_depth`.
    fn keyTarget(self: *Parser, base: *Table, base_depth: usize) !Target {
        try self.keyPath(base_depth);
        self.skipSpace();
        if (self.peek() != '=') return self.failFound("expected '=' after the key");
        self.pos += 1;
        self.skipSpace();

        const keys = self.keys.items;
        var table = base;
        for (keys[0 .. keys.len - 1], 0..) |key, index| {
            switch (table.get(.{ .string = key.name })) {
                .nil => {
                    const created = try self.newTable(.object, .dotted);
                    try self.set(table, key.name, .{ .table = created });
                    table = created;
                },
                .table => |existing| {
                    const meta = self.meta.getPtr(existing).?;
                    switch (meta.origin) {
                        .dotted => {},
                        .implicit => meta.origin = .dotted,
                        .header => return self.fail(key.pos, "table '{f}' is defined by a header and cannot be extended with dotted keys", .{self.path(index + 1)}),
                        .inline_table => return self.fail(key.pos, "inline table '{f}' cannot be extended", .{self.path(index + 1)}),
                        .static_array, .table_array => return self.fail(key.pos, "'{f}' is an array, not a table", .{self.path(index + 1)}),
                    }
                    table = existing;
                },
                else => return self.fail(key.pos, "'{f}' already has a value that is not a table", .{self.path(index + 1)}),
            }
        }
        const last = keys[keys.len - 1];
        if (table.get(.{ .string = last.name }) != .nil) return self.fail(last.pos, "duplicate key '{f}'", .{self.path(keys.len)});
        return .{ .table = table, .key = last.name, .depth = base_depth + keys.len - 1 };
    }

    /// Parses a dotted key into `keys`. `base_depth` is the depth of the table it is relative to.
    fn keyPath(self: *Parser, base_depth: usize) !void {
        self.keys.clearRetainingCapacity();
        while (true) {
            if (base_depth + self.keys.items.len >= data.max_depth) return self.fail(self.pos, "nesting deeper than {d} levels", .{data.max_depth});
            const start = self.pos;
            const byte = self.peek() orelse return self.failFound("expected a key");
            const name: []const u8 = switch (byte) {
                '"' => blk: {
                    if (std.mem.startsWith(u8, self.input[self.pos..], "\"\"\"")) return self.fail(start, "keys cannot be multi-line strings", .{});
                    break :blk try self.basicString(false);
                },
                '\'' => blk: {
                    if (std.mem.startsWith(u8, self.input[self.pos..], "'''")) return self.fail(start, "keys cannot be multi-line strings", .{});
                    break :blk try self.literalString(false);
                },
                else => blk: {
                    while (self.pos < self.input.len and isBareKeyByte(self.input[self.pos])) self.pos += 1;
                    if (self.pos == start) return self.failFound("expected a key");
                    break :blk self.input[start..self.pos];
                },
            };
            try self.keys.append(self.state.allocator, .{ .name = try self.state.strings.intern(name), .pos = start });
            self.skipSpace();
            if (self.peek() != '.') return;
            self.pos += 1;
            self.skipSpace();
        }
    }

    fn value(self: *Parser, first: Target) !void {
        const allocator = self.state.allocator;
        self.frames.clearRetainingCapacity();
        var target = first;
        next: while (true) {
            const start = self.pos;
            const byte = self.peek() orelse return self.failFound("expected a value");
            switch (byte) {
                '[', '{' => {
                    if (target.depth >= data.max_depth) return self.fail(start, "nesting deeper than {d} levels", .{data.max_depth});
                    self.pos += 1;
                    const is_array = byte == '[';
                    const table = try self.newTable(if (is_array) .array else .object, if (is_array) .static_array else .inline_table);
                    try self.store(&target, .{ .table = table });
                    try self.frames.append(allocator, .{ .kind = if (is_array) .array else .inline_table, .table = table, .depth = target.depth + 1 });
                    if (is_array) {
                        try self.skipArraySpace();
                        if (self.peek() == ']') {
                            self.pos += 1;
                            _ = self.frames.pop();
                        } else {
                            target = .{ .table = table, .key = null, .depth = target.depth + 1 };
                            continue :next;
                        }
                    } else {
                        try self.skipArraySpace();
                        if (self.peek() == '}') {
                            self.pos += 1;
                            _ = self.frames.pop();
                        } else {
                            target = try self.keyTarget(table, target.depth + 1);
                            continue :next;
                        }
                    }
                },
                else => try self.store(&target, try self.scalar()),
            }

            while (self.frames.items.len != 0) {
                const frame = &self.frames.items[self.frames.items.len - 1];
                switch (frame.kind) {
                    .array => {
                        try self.skipArraySpace();
                        const next = self.peek() orelse return self.failFound("expected ',' or ']' in the array");
                        if (next == ']') {
                            self.pos += 1;
                            _ = self.frames.pop();
                            continue;
                        }
                        if (next != ',') return self.failFound("expected ',' or ']' in the array");
                        self.pos += 1;
                        try self.skipArraySpace();
                        if (self.peek() == ']') {
                            self.pos += 1;
                            _ = self.frames.pop();
                            continue;
                        }
                        target = .{ .table = frame.table, .key = null, .depth = frame.depth };
                        continue :next;
                    },
                    .inline_table => {
                        try self.skipArraySpace();
                        const next = self.peek() orelse return self.failFound("expected ',' or '}}' in the inline table");
                        if (next == '}') {
                            self.pos += 1;
                            _ = self.frames.pop();
                            continue;
                        }
                        if (next != ',') return self.failFound("expected ',' or '}}' in the inline table");
                        self.pos += 1;
                        try self.skipArraySpace();
                        if (self.peek() == '}') {
                            self.pos += 1;
                            _ = self.frames.pop();
                            continue;
                        }
                        target = try self.keyTarget(frame.table, frame.depth);
                        continue :next;
                    },
                }
            }
            return;
        }
    }

    fn store(self: *Parser, target: *Target, item: Value) !void {
        if (target.key) |key| return self.set(target.table, key, item);
        const frame = &self.frames.items[self.frames.items.len - 1];
        try self.state.budget.charge(4);
        try self.state.setTableRaw(frame.table, .{ .integer = frame.next_index }, item);
        frame.next_index += 1;
    }

    fn set(self: *Parser, table: *Table, key: *const String, item: Value) !void {
        try self.state.budget.charge(4);
        try self.state.setTableRaw(table, .{ .string = key }, item);
    }

    fn newTable(self: *Parser, kind: enum { object, array }, origin: Origin) !*Table {
        try self.meta.ensureUnusedCapacity(self.state.allocator, 1);
        const table = (try self.state.newTableWithHints(0, 0)).table;
        const tables = &self.state.library_tables;
        const metatable = if (kind == .array) tables.get(.data_array_metatable).? else tables.get(.data_object_metatable).?;
        try metatable_mod.setTableMetatableRaw(self.state, table, metatable);
        self.meta.putAssumeCapacity(table, .{ .origin = origin });
        return table;
    }

    fn originOf(self: *Parser, table: *Table) Origin {
        return self.meta.get(table).?.origin;
    }

    fn path(self: *Parser, len: usize) KeyPath {
        return .{ .keys = self.keys.items[0..len] };
    }

    fn scalar(self: *Parser) !Value {
        const start = self.pos;
        const rest = self.input[self.pos..];
        switch (rest[0]) {
            '"' => return self.stringValue(try self.basicString(std.mem.startsWith(u8, rest, "\"\"\""))),
            '\'' => return self.stringValue(try self.literalString(std.mem.startsWith(u8, rest, "'''"))),
            't' => if (std.mem.startsWith(u8, rest, "true")) {
                self.pos += 4;
                return .{ .boolean = true };
            },
            'f' => if (std.mem.startsWith(u8, rest, "false")) {
                self.pos += 5;
                return .{ .boolean = false };
            },
            '0'...'9' => if (looksLikeDateTime(rest)) return self.dateTime(),
            else => {},
        }
        if (!isNumberByte(rest[0])) return self.failFound("expected a value");
        while (self.pos < self.input.len and isNumberByte(self.input[self.pos])) self.pos += 1;
        return self.number(start, self.input[start..self.pos]);
    }

    fn stringValue(self: *Parser, bytes: []const u8) !Value {
        return .{ .string = try self.state.strings.intern(bytes) };
    }

    fn number(self: *Parser, start: usize, text: []const u8) !Value {
        var body = text;
        var negative = false;
        if (body[0] == '+' or body[0] == '-') {
            negative = body[0] == '-';
            body = body[1..];
        }
        if (std.mem.eql(u8, body, "inf")) return .{ .number = if (negative) -std.math.inf(f64) else std.math.inf(f64) };
        if (std.mem.eql(u8, body, "nan")) return .{ .number = if (negative) -std.math.nan(f64) else std.math.nan(f64) };
        if (body.len == 0 or !std.ascii.isDigit(body[0])) return self.fail(start, "invalid value '{s}'", .{text});

        if (body.len > 2 and body[0] == '0' and (body[1] == 'x' or body[1] == 'o' or body[1] == 'b')) {
            if (body.len != text.len) return self.fail(start, "prefixed integers cannot have a sign", .{});
            const base: u8 = switch (body[1]) {
                'x' => 16,
                'o' => 8,
                else => 2,
            };
            const digits = try self.stripUnderscores(start, body[2..], base);
            const magnitude = std.fmt.parseInt(u64, digits, base) catch return self.fail(start, "invalid integer '{s}'", .{text});
            return .{ .integer = std.math.cast(i64, magnitude) orelse return self.fail(start, "integer {s} is outside the 64-bit range", .{text}) };
        }

        const int_end = std.mem.indexOfAny(u8, body, ".eE") orelse body.len;
        const int_part = body[0..int_end];
        if (int_part.len == 0) return self.fail(start, "invalid number '{s}'", .{text});
        if (int_part.len > 1 and int_part[0] == '0') return self.fail(start, "leading zeros are not allowed in '{s}'", .{text});
        _ = try self.stripUnderscores(start, int_part, 10);

        if (int_end == body.len) {
            _ = try self.stripUnderscores(start, body, 10);
            if (negative) try self.scratch.insert(self.state.allocator, 0, '-');
            return .{ .integer = std.fmt.parseInt(i64, self.scratch.items, 10) catch return self.fail(start, "integer {s} is outside the 64-bit range", .{text}) };
        }

        var rest = body[int_end..];
        if (rest[0] == '.') {
            const frac_end = std.mem.indexOfAny(u8, rest[1..], "eE") orelse rest.len - 1;
            if (frac_end == 0) return self.fail(start, "expected digits after the decimal point in '{s}'", .{text});
            _ = try self.stripUnderscores(start, rest[1 .. frac_end + 1], 10);
            rest = rest[frac_end + 1 ..];
        }
        if (rest.len != 0) {
            var exponent = rest[1..];
            if (exponent.len != 0 and (exponent[0] == '+' or exponent[0] == '-')) exponent = exponent[1..];
            if (exponent.len == 0) return self.fail(start, "expected digits in the exponent of '{s}'", .{text});
            _ = try self.stripUnderscores(start, exponent, 10);
        }
        const digits = try self.stripUnderscores(start, text, 0);
        return .{ .number = std.fmt.parseFloat(f64, digits) catch return self.fail(start, "invalid number '{s}'", .{text}) };
    }

    /// Checks that underscores in `text` sit between digits of `base` and returns it without them.
    /// A `base` of 0 skips the digit check.
    fn stripUnderscores(self: *Parser, start: usize, text: []const u8, base: u8) ![]const u8 {
        self.scratch.clearRetainingCapacity();
        var previous_digit = false;
        for (text, 0..) |byte, index| {
            if (byte == '_') {
                const next_digit = index + 1 < text.len and isDigitOf(text[index + 1], if (base == 0) 10 else base);
                if (!previous_digit or !next_digit) return self.fail(start, "underscores must sit between digits", .{});
                previous_digit = false;
                continue;
            }
            const is_digit = isDigitOf(byte, if (base == 0) 10 else base);
            if (base != 0 and !is_digit) return self.fail(start, "invalid digit {f} in number", .{data.ByteText{ .byte = byte }});
            previous_digit = is_digit;
            try self.scratch.append(self.state.allocator, byte);
        }
        if (self.scratch.items.len == 0) return self.fail(start, "expected digits", .{});
        return self.scratch.items;
    }

    fn dateTime(self: *Parser) !Value {
        var failure: datetime.Failure = undefined;
        const parsed, const end = datetime.scan(self.input, self.pos, &failure) catch return self.fail(failure.offset, "{s}", .{failure.message});
        self.pos = end;
        return datetime.toLua(self.state, parsed);
    }

    /// Reads a basic string at its opening quote. The result is valid until the next call.
    fn basicString(self: *Parser, multiline: bool) ![]const u8 {
        const allocator = self.state.allocator;
        const start = self.pos;
        self.pos += if (multiline) 3 else 1;
        if (multiline) self.skipFirstNewline();
        self.scratch.clearRetainingCapacity();
        while (true) {
            const run_start = self.pos;
            while (self.pos < self.input.len and isBasicPlain(self.input[self.pos])) self.pos += 1;
            try self.scratch.appendSlice(allocator, self.input[run_start..self.pos]);

            const byte = self.peek() orelse return self.fail(start, "unterminated string", .{});
            switch (byte) {
                '"' => if (try self.closeQuotes(start, '"', multiline)) return self.scratch.items,
                '\\' => try self.escape(multiline),
                '\n', '\r' => {
                    if (!multiline) return self.fail(start, "unterminated string", .{});
                    try self.stringNewline();
                },
                else => return self.fail(self.pos, "control character in string", .{}),
            }
        }
    }

    /// Reads a literal string at its opening quote. The result is valid until the next call.
    fn literalString(self: *Parser, multiline: bool) ![]const u8 {
        const start = self.pos;
        self.pos += if (multiline) 3 else 1;
        if (multiline) self.skipFirstNewline();
        self.scratch.clearRetainingCapacity();
        while (true) {
            const run_start = self.pos;
            while (self.pos < self.input.len and isLiteralPlain(self.input[self.pos])) self.pos += 1;
            try self.scratch.appendSlice(self.state.allocator, self.input[run_start..self.pos]);

            const byte = self.peek() orelse return self.fail(start, "unterminated string", .{});
            switch (byte) {
                '\'' => if (try self.closeQuotes(start, '\'', multiline)) return self.scratch.items,
                '\n', '\r' => {
                    if (!multiline) return self.fail(start, "unterminated string", .{});
                    try self.stringNewline();
                },
                else => return self.fail(self.pos, "control character in string", .{}),
            }
        }
    }

    fn skipFirstNewline(self: *Parser) void {
        if (std.mem.startsWith(u8, self.input[self.pos..], "\n")) {
            self.pos += 1;
        } else if (std.mem.startsWith(u8, self.input[self.pos..], "\r\n")) {
            self.pos += 2;
        }
    }

    fn stringNewline(self: *Parser) !void {
        const allocator = self.state.allocator;
        if (self.input[self.pos] == '\r') {
            if (self.pos + 1 == self.input.len or self.input[self.pos + 1] != '\n') return self.fail(self.pos, "carriage return without a line feed", .{});
            try self.scratch.append(allocator, '\r');
            self.pos += 1;
        }
        try self.scratch.append(allocator, '\n');
        self.pos += 1;
    }

    /// Handles a run of `quote` bytes; returns true when it closes the string.
    fn closeQuotes(self: *Parser, start: usize, quote: u8, multiline: bool) !bool {
        if (!multiline) {
            self.pos += 1;
            return true;
        }
        var count: usize = 0;
        while (self.pos + count < self.input.len and self.input[self.pos + count] == quote) count += 1;
        self.pos += count;
        if (count < 3) {
            try self.scratch.appendNTimes(self.state.allocator, quote, count);
            return false;
        }
        if (count > 5) return self.fail(start, "too many quotes at the end of the string", .{});
        try self.scratch.appendNTimes(self.state.allocator, quote, count - 3);
        return true;
    }

    fn escape(self: *Parser, multiline: bool) !void {
        const allocator = self.state.allocator;
        const escape_start = self.pos;
        self.pos += 1;
        const kind = self.peek() orelse return self.fail(escape_start, "unterminated string", .{});
        self.pos += 1;
        const decoded: u8 = switch (kind) {
            'b' => 0x08,
            't' => '\t',
            'n' => '\n',
            'f' => 0x0c,
            'r' => '\r',
            'e' => 0x1b,
            '"' => '"',
            '\\' => '\\',
            'x', 'u', 'U' => {
                const len: usize = switch (kind) {
                    'x' => 2,
                    'u' => 4,
                    else => 8,
                };
                if (self.input.len - self.pos < len) return self.fail(escape_start, "\\{c} escape needs {d} hex digits", .{ kind, len });
                const codepoint = std.fmt.parseInt(u32, self.input[self.pos..][0..len], 16) catch return self.fail(escape_start, "\\{c} escape needs {d} hex digits", .{ kind, len });
                self.pos += len;
                const scalar_value = std.math.cast(u21, codepoint) orelse return self.fail(escape_start, "\\{c} escape is not a Unicode scalar value", .{kind});
                var buffer: [4]u8 = undefined;
                const encoded = std.unicode.utf8Encode(scalar_value, &buffer) catch return self.fail(escape_start, "\\{c} escape is not a Unicode scalar value", .{kind});
                try self.scratch.appendSlice(allocator, buffer[0..encoded]);
                return;
            },
            ' ', '\t', '\n', '\r' => {
                if (!multiline) return self.fail(escape_start, "invalid escape '\\{c}'", .{kind});
                self.pos -= 1;
                self.skipSpace();
                if (self.peek() != '\n' and self.peek() != '\r') return self.fail(escape_start, "a line-ending backslash must be followed only by whitespace", .{});
                while (self.peek()) |byte| switch (byte) {
                    ' ', '\t' => self.pos += 1,
                    '\n', '\r' => try self.newline(),
                    else => break,
                };
                return;
            },
            else => return self.fail(escape_start, "invalid escape {f}", .{data.ByteText{ .byte = kind }}),
        };
        try self.scratch.append(allocator, decoded);
    }

    fn peek(self: *const Parser) ?u8 {
        return if (self.pos < self.input.len) self.input[self.pos] else null;
    }

    fn skipSpace(self: *Parser) void {
        while (self.pos < self.input.len and (self.input[self.pos] == ' ' or self.input[self.pos] == '\t')) self.pos += 1;
    }

    fn skipArraySpace(self: *Parser) !void {
        while (self.peek()) |byte| switch (byte) {
            ' ', '\t' => self.pos += 1,
            '\n', '\r' => try self.newline(),
            '#' => try self.comment(),
            else => return,
        };
    }

    fn newline(self: *Parser) !void {
        if (self.input[self.pos] == '\r') {
            if (self.pos + 1 == self.input.len or self.input[self.pos + 1] != '\n') return self.fail(self.pos, "carriage return without a line feed", .{});
            self.pos += 1;
        }
        self.pos += 1;
    }

    fn comment(self: *Parser) !void {
        while (self.peek()) |byte| {
            if (byte == '\n' or (byte == '\r' and self.pos + 1 < self.input.len and self.input[self.pos + 1] == '\n')) return;
            if (isControl(byte)) return self.fail(self.pos, "control character in comment", .{});
            self.pos += 1;
        }
    }

    fn endOfLine(self: *Parser) !void {
        self.skipSpace();
        if (self.peek() == '#') try self.comment();
        const byte = self.peek() orelse return;
        if (byte != '\n' and byte != '\r') return self.failFound("expected a line break");
        try self.newline();
    }
};

const KeyPath = struct {
    keys: []const Key,

    pub fn format(self: KeyPath, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.keys, 0..) |key, index| {
            if (index != 0) try writer.writeByte('.');
            try writeKey(writer, key.name.bytes());
        }
    }
};

fn firstInvalidUtf8(input: []const u8) ?usize {
    if (std.unicode.utf8ValidateSlice(input)) return null;
    var index: usize = 0;
    while (index < input.len) {
        const len = std.unicode.utf8ByteSequenceLength(input[index]) catch return index;
        if (index + len > input.len) return index;
        _ = std.unicode.utf8Decode(input[index..][0..len]) catch return index;
        index += len;
    }
    return null;
}

fn isControl(byte: u8) bool {
    return (byte < 0x20 and byte != '\t') or byte == 0x7f;
}

fn isBasicPlain(byte: u8) bool {
    return !isControl(byte) and byte != '"' and byte != '\\';
}

fn isLiteralPlain(byte: u8) bool {
    return !isControl(byte) and byte != '\'';
}

fn isBareKeyByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-';
}

fn isNumberByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.' or byte == '+' or byte == '-';
}

fn isDigitOf(byte: u8, base: u8) bool {
    const digit = std.fmt.charToDigit(byte, 16) catch return false;
    return digit < base;
}

fn looksLikeDateTime(bytes: []const u8) bool {
    if (bytes.len >= 5 and std.ascii.isDigit(bytes[1]) and std.ascii.isDigit(bytes[2]) and std.ascii.isDigit(bytes[3]) and bytes[4] == '-') return true;
    return bytes.len >= 3 and std.ascii.isDigit(bytes[1]) and bytes[2] == ':';
}

pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0) return state.failArgumentMessage("toml.write", 1, "value expected");
    var writer: Writer = .{ .walker = .init(state, "toml.write"), .value = runtime.argValue(state, thread, op, 0) };
    if (try data.optionsTable(state, thread, op, "toml.write")) |table| {
        if (try data.enumOption(state, table, "toml.write", "layout", Layout, &.{
            .{ &.{ "inline_tables", "inline" }, .inline_tables },
            .{ &.{"sections"}, .sections },
        }, "layout must be 'inline_tables' or 'sections'")) |layout| writer.layout = layout;
    }
    try data.returnEncoded(state, thread, op, "toml.write", &writer, Writer.encode);
}

const Layout = enum { inline_tables, sections };

const Writer = struct {
    const Placement = enum { inline_value, section, table_array };

    walker: data.Walker,
    value: Value,
    layout: Layout = .inline_tables,
    header: [data.max_depth][]const u8 = undefined,
    header_len: usize = 0,
    wrote_any: bool = false,

    fn encode(self: *Writer, out: *std.Io.Writer) !void {
        const root = switch (self.value) {
            .table => |table| table,
            else => return self.walker.fail("expected a table with named fields, got a {s} value", .{runtime.typeName(self.value)}),
        };
        switch (try self.walker.enter(root)) {
            .object => {},
            .array => |len| if (len != 0) return self.walker.fail("expected a table with named fields, got an array", .{}),
            .null => return self.walker.fail("TOML has no null value", .{}),
            .datetime => return self.walker.fail("expected a table with named fields, got a datetime", .{}),
            .extension => return self.walker.fail("cannot encode a MessagePack extension", .{}),
        }
        defer self.walker.leave();
        self.wrote_any = try self.writeBody(out, root, false);
        if (self.layout == .sections) try self.writeSections(out, root);
    }

    /// Writes the `key = value` lines of `table`, skipping entries written as sections.
    /// `after_header` starts the first line on a new line.
    fn writeBody(self: *Writer, out: *std.Io.Writer, table: *Table, after_header: bool) anyerror!bool {
        var wrote = false;
        for (table.entries()) |entry| {
            if (entry.value == .nil) continue;
            const name = entry.key.string.bytes();
            self.walker.step(.{ .key = name });
            if (self.layout == .sections and try self.placement(entry.value) != .inline_value) continue;
            if (wrote or after_header) try out.writeByte('\n');
            try self.writeKeyChecked(out, name);
            try out.writeAll(" = ");
            try self.writeValue(out, entry.value);
            wrote = true;
        }
        return wrote;
    }

    fn writeSections(self: *Writer, out: *std.Io.Writer, table: *Table) anyerror!void {
        for (table.entries()) |entry| {
            if (entry.value == .nil) continue;
            const name = entry.key.string.bytes();
            self.walker.step(.{ .key = name });
            const kind = try self.placement(entry.value);
            if (kind == .inline_value) continue;
            const child = entry.value.table;
            try self.walker.visit(entry.value);
            _ = try self.walker.enter(child);
            defer self.walker.leave();
            self.header[self.header_len] = name;
            self.header_len += 1;
            defer self.header_len -= 1;

            if (kind == .section) {
                try self.writeSection(out, child, "[", "]");
                continue;
            }
            var index: i64 = 1;
            while (true) : (index += 1) {
                const item = child.get(.{ .integer = index });
                if (item == .nil) break;
                self.walker.step(.{ .index = @intCast(index) });
                try self.walker.visit(item);
                _ = try self.walker.enter(item.table);
                defer self.walker.leave();
                try self.writeSection(out, item.table, "[[", "]]");
            }
        }
    }

    fn writeSection(self: *Writer, out: *std.Io.Writer, table: *Table, comptime open: []const u8, comptime close: []const u8) anyerror!void {
        if (self.wrote_any) try out.writeAll("\n\n");
        try out.writeAll(open);
        for (self.header[0..self.header_len], 0..) |part, index| {
            if (index != 0) try out.writeByte('.');
            try self.writeKeyChecked(out, part);
        }
        try out.writeAll(close);
        _ = try self.writeBody(out, table, true);
        self.wrote_any = true;
        try self.writeSections(out, table);
    }

    fn placement(self: *Writer, item: Value) !Placement {
        const table = switch (item) {
            .table => |table| table,
            else => return .inline_value,
        };
        switch (try self.walker.classify(table)) {
            .null, .datetime, .extension => return .inline_value,
            .object => return .section,
            .array => |len| {
                if (len == 0) return .inline_value;
                for (1..len + 1) |index| {
                    const element = table.get(.{ .integer = @intCast(index) });
                    if (element != .table) return .inline_value;
                    if (try self.walker.classify(element.table) != .object) return .inline_value;
                }
                return .table_array;
            },
        }
    }

    fn writeValue(self: *Writer, out: *std.Io.Writer, item: Value) anyerror!void {
        try self.walker.visit(item);
        switch (item) {
            .boolean => |boolean| try out.writeAll(if (boolean) "true" else "false"),
            .integer => |integer| try out.print("{d}", .{integer}),
            .number => |number| {
                if (std.math.isNan(number)) {
                    try out.writeAll("nan");
                } else if (std.math.isInf(number)) {
                    try out.writeAll(if (number < 0) "-inf" else "inf");
                } else {
                    try data.writeFloat(out, number);
                }
            },
            .string => |string| try self.writeStringChecked(out, string.bytes()),
            .table => |table| switch (try self.walker.enter(table)) {
                .null => return self.walker.fail("TOML has no null value", .{}),
                .datetime => |moment| {
                    if (moment.date) |date| if (date.year < 0 or date.year > 9999) return self.walker.fail("TOML years must be between 0 and 9999", .{});
                    try out.print("{f}", .{moment});
                },
                .extension => return self.walker.fail("cannot encode a MessagePack extension", .{}),
                .array => |len| {
                    defer self.walker.leave();
                    try out.writeByte('[');
                    for (1..len + 1) |index| {
                        if (index != 1) try out.writeAll(", ");
                        self.walker.step(.{ .index = index });
                        try self.writeValue(out, table.get(.{ .integer = @intCast(index) }));
                    }
                    try out.writeByte(']');
                },
                .object => |count| {
                    defer self.walker.leave();
                    if (count == 0) return out.writeAll("{}");
                    try out.writeAll("{ ");
                    var written: usize = 0;
                    for (table.entries()) |entry| {
                        if (entry.value == .nil) continue;
                        const name = entry.key.string.bytes();
                        self.walker.step(.{ .key = name });
                        if (written != 0) try out.writeAll(", ");
                        try self.writeKeyChecked(out, name);
                        try out.writeAll(" = ");
                        try self.writeValue(out, entry.value);
                        written += 1;
                    }
                    try out.writeAll(" }");
                },
            },
            else => return self.walker.failValue(item),
        }
    }

    fn writeKeyChecked(self: *Writer, out: *std.Io.Writer, key: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(key)) return self.walker.fail("key is not valid UTF-8", .{});
        try writeKey(out, key);
    }

    fn writeStringChecked(self: *Writer, out: *std.Io.Writer, bytes: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(bytes)) return self.walker.fail("string is not valid UTF-8", .{});
        try writeString(out, bytes);
    }
};

fn writeKey(out: *std.Io.Writer, key: []const u8) std.Io.Writer.Error!void {
    for (key) |byte| {
        if (!isBareKeyByte(byte)) return writeString(out, key);
    }
    if (key.len == 0) return writeString(out, key);
    try out.writeAll(key);
}

fn writeString(out: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!void {
    try out.writeByte('"');
    var run_start: usize = 0;
    for (bytes, 0..) |byte, index| {
        const escaped: []const u8 = switch (byte) {
            0x08 => "\\b",
            '\t' => "\\t",
            '\n' => "\\n",
            0x0c => "\\f",
            '\r' => "\\r",
            '"' => "\\\"",
            '\\' => "\\\\",
            0x00...0x07, 0x0b, 0x0e...0x1f, 0x7f => {
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
