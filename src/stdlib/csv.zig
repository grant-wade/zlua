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

const RecordTerminator = enum { lf, crlf };

const Options = struct {
    delimiter: u8 = ',',
    header: bool = true,
    record_terminator: RecordTerminator = .crlf,
    final_record_terminator: bool = false,
};

fn readOptions(state: *State, thread: *Thread, op: bytecode.Call, operation: []const u8) !Options {
    var options: Options = .{};
    const table = try data.optionsTable(state, thread, op, operation) orelse return options;
    if (try data.enumOption(state, table, operation, "delimiter", u8, &.{
        .{ &.{ "comma", "," }, ',' },
        .{ &.{ "tab", "tsv", "\t" }, '\t' },
    }, "delimiter must be 'comma' or 'tab'")) |delimiter| options.delimiter = delimiter;
    if (try data.boolOption(state, table, operation, "header")) |header| options.header = header;
    if (try data.enumOption(state, table, operation, "record_terminator", RecordTerminator, &.{
        .{ &.{ "lf", "\n" }, .lf },
        .{ &.{ "crlf", "\r\n" }, .crlf },
    }, "record_terminator must be 'lf' or 'crlf'")) |terminator| options.record_terminator = terminator;
    if (try data.boolOption(state, table, operation, "final_record_terminator")) |final| options.final_record_terminator = final;
    return options;
}

pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const input = try data.inputBytes(state, runtime.argValue(state, thread, op, 0), "csv.read");
    const options = try readOptions(state, thread, op, "csv.read");
    var reader: Reader = .{ .state = state, .input = input, .delimiter = options.delimiter, .builder = .init(state) };
    defer reader.deinit();
    try data.returnValue(state, thread, op, try reader.document(options.header));
}

const Reader = struct {
    const End = enum { cell, record, input };

    state: *State,
    input: []const u8,
    delimiter: u8,
    pos: usize = 0,
    builder: data.Builder,
    scratch: std.ArrayList(u8) = .empty,
    header: std.ArrayList([]u8) = .empty,

    fn deinit(self: *Reader) void {
        const allocator = self.state.allocator;
        self.builder.deinit();
        self.scratch.deinit(allocator);
        for (self.header.items) |name| allocator.free(name);
        self.header.deinit(allocator);
    }

    fn fail(self: *Reader, offset: usize, comptime fmt: []const u8, args: anytype) runtime.RuntimeError {
        return data.failAtLine(self.state, "csv.read", self.input, offset, fmt, args);
    }

    fn document(self: *Reader, has_header: bool) !Value {
        const allocator = self.state.allocator;
        const b = &self.builder;
        if (has_header) {
            if (self.input.len == 0) return self.fail(0, "missing header row", .{});
            while (true) {
                const cell, const end = try self.nextCell();
                const name = try allocator.dupe(u8, cell);
                self.header.append(allocator, name) catch |err| {
                    allocator.free(name);
                    return err;
                };
                if (end != .cell) break;
            }
        }

        try b.begin(.array, 0);
        var key_buffer: [20]u8 = undefined;
        while (self.pos < self.input.len) {
            const record_start = self.pos;
            try b.begin(.object, self.header.items.len);
            var column: usize = 0;
            while (true) : (column += 1) {
                const cell_start = self.pos;
                const cell, const end = try self.nextCell();
                if (has_header) {
                    if (column == self.header.items.len) return self.fail(cell_start, "record has more fields than the header's {d}", .{self.header.items.len});
                    try b.setKey(self.header.items[column]);
                } else {
                    try b.setKey(std.fmt.bufPrint(&key_buffer, "{d}", .{column}) catch unreachable);
                }
                if (cell.len == 0) try b.appendNull() else try b.appendString(cell);
                if (end != .cell) break;
            }
            if (has_header and column + 1 != self.header.items.len) {
                return self.fail(record_start, "record has {d} of the header's {d} fields", .{ column + 1, self.header.items.len });
            }
            try b.end();
        }
        try b.end();
        return b.root;
    }

    /// Reads one cell and the separator after it. The bytes are valid until the next call.
    fn nextCell(self: *Reader) !struct { []const u8, End } {
        const input = self.input;
        const start = self.pos;
        var bytes: []const u8 = undefined;
        if (self.pos < input.len and input[self.pos] == '"') {
            self.pos += 1;
            self.scratch.clearRetainingCapacity();
            while (true) {
                const close = std.mem.indexOfScalarPos(u8, input, self.pos, '"') orelse return self.fail(start, "unterminated quoted field", .{});
                try self.scratch.appendSlice(self.state.allocator, input[self.pos..close]);
                self.pos = close + 1;
                if (self.pos < input.len and input[self.pos] == '"') {
                    try self.scratch.append(self.state.allocator, '"');
                    self.pos += 1;
                    continue;
                }
                break;
            }
            bytes = self.scratch.items;
            if (self.pos < input.len and !self.isSeparator(input[self.pos])) {
                return self.fail(self.pos, "expected a delimiter or line break after the closing quote, found {f}", .{data.ByteText{ .byte = input[self.pos] }});
            }
        } else {
            while (self.pos < input.len and !self.isSeparator(input[self.pos])) : (self.pos += 1) {
                if (input[self.pos] == '"') return self.fail(self.pos, "quote inside an unquoted field", .{});
            }
            bytes = input[start..self.pos];
        }

        if (self.pos == input.len) return .{ bytes, .input };
        const separator = input[self.pos];
        self.pos += 1;
        if (separator == self.delimiter) return .{ bytes, .cell };
        if (separator == '\r') {
            if (self.pos == input.len or input[self.pos] != '\n') return self.fail(self.pos - 1, "carriage return without a line feed", .{});
            self.pos += 1;
        }
        return .{ bytes, .record };
    }

    fn isSeparator(self: *const Reader, byte: u8) bool {
        return byte == self.delimiter or byte == '\n' or byte == '\r';
    }
};

pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0) return state.failArgumentMessage("csv.write", 1, "value expected");
    var writer: Writer = .{
        .walker = .init(state, "csv.write"),
        .value = runtime.argValue(state, thread, op, 0),
        .options = try readOptions(state, thread, op, "csv.write"),
    };
    defer writer.deinit();
    try data.returnEncoded(state, thread, op, "csv.write", &writer, Writer.encode);
}

const Writer = struct {
    walker: data.Walker,
    value: Value,
    options: Options,
    columns: std.ArrayList([]u8) = .empty,
    column_index: std.StringHashMapUnmanaged(usize) = .empty,
    cells: std.ArrayList(Value) = .empty,
    path: std.ArrayList(u8) = .empty,

    fn deinit(self: *Writer) void {
        const allocator = self.walker.state.allocator;
        for (self.columns.items) |column| allocator.free(column);
        self.columns.deinit(allocator);
        self.column_index.deinit(allocator);
        self.cells.deinit(allocator);
        self.path.deinit(allocator);
    }

    fn encode(self: *Writer, out: *std.Io.Writer) !void {
        const rows = switch (self.value) {
            .table => |table| table,
            else => return self.walker.fail("expected an array of rows, got a {s} value", .{runtime.typeName(self.value)}),
        };
        const count = switch (try self.walker.enter(rows)) {
            .array => |len| len,
            .object => |fields| if (fields == 0) 0 else return self.walker.fail("expected an array of rows, got a table with named fields", .{}),
            .null => return self.walker.fail("expected an array of rows, got null", .{}),
        };
        defer self.walker.leave();
        if (count == 0) return self.walker.fail("needs at least one row", .{});

        for (1..count + 1) |index| {
            self.walker.step(.{ .index = index });
            const row = rows.get(.{ .integer = @intCast(index) });
            try self.walker.visit(row);
            const row_table = switch (row) {
                .table => |table| table,
                else => return self.walker.fail("row must be a table with named fields, got a {s} value", .{runtime.typeName(row)}),
            };
            if (index == 1) {
                try self.collect(row_table, true);
                if (self.columns.items.len == 0) return self.walker.fail("the first row has no fields", .{});
                if (self.options.header) {
                    for (self.columns.items, 0..) |column, i| {
                        if (i != 0) try out.writeByte(self.options.delimiter);
                        try self.writeEscaped(out, column);
                    }
                    try self.terminate(out);
                }
            } else {
                @memset(self.cells.items, .nil);
                try self.collect(row_table, false);
                try self.terminate(out);
            }
            for (self.cells.items, 0..) |cell, i| {
                if (i != 0) try out.writeByte(self.options.delimiter);
                try self.writeCell(out, cell);
            }
        }
        if (self.options.final_record_terminator) try self.terminate(out);
    }

    fn terminate(self: *Writer, out: *std.Io.Writer) !void {
        try out.writeAll(if (self.options.record_terminator == .lf) "\n" else "\r\n");
    }

    /// Places the leaves of `table` into `cells`, defining the columns when `first`.
    fn collect(self: *Writer, table: *Table, first: bool) anyerror!void {
        const allocator = self.walker.state.allocator;
        const is_row = self.walker.depth == 1;
        switch (try self.walker.enter(table)) {
            .object => {},
            .array => |len| if (len != 0) {
                if (is_row) return self.walker.fail("row must be a table with named fields, got an array", .{});
                return self.walker.fail("nested arrays are not supported", .{});
            },
            .null => return self.walker.fail("row must be a table with named fields, got null", .{}),
        }
        defer self.walker.leave();
        const prefix_len = self.path.items.len;
        defer self.path.shrinkRetainingCapacity(prefix_len);

        for (table.entries()) |entry| {
            if (entry.value == .nil) continue;
            const name = entry.key.string.bytes();
            self.walker.step(.{ .key = name });
            self.path.shrinkRetainingCapacity(prefix_len);
            if (prefix_len != 0) try self.path.append(allocator, '.');
            try self.path.appendSlice(allocator, name);

            if (entry.value == .table and !self.walker.isNull(entry.value.table)) {
                try self.walker.visit(entry.value);
                try self.collect(entry.value.table, first);
                continue;
            }
            if (first) {
                const gop = try self.column_index.getOrPut(allocator, self.path.items);
                if (gop.found_existing) return self.walker.fail("duplicate column '{s}'", .{self.path.items});
                errdefer _ = self.column_index.remove(self.path.items);
                try self.columns.ensureUnusedCapacity(allocator, 1);
                try self.cells.ensureUnusedCapacity(allocator, 1);
                const column = try allocator.dupe(u8, self.path.items);
                gop.key_ptr.* = column;
                gop.value_ptr.* = self.columns.items.len;
                self.columns.appendAssumeCapacity(column);
                self.cells.appendAssumeCapacity(entry.value);
            } else {
                const index = self.column_index.get(self.path.items) orelse return self.walker.fail("column '{s}' is not in the first row", .{self.path.items});
                self.cells.items[index] = entry.value;
            }
        }
    }

    fn writeCell(self: *Writer, out: *std.Io.Writer, value: Value) !void {
        try self.walker.visit(value);
        switch (value) {
            .nil => {},
            .boolean => |boolean| try out.writeAll(if (boolean) "true" else "false"),
            .integer => |integer| try out.print("{d}", .{integer}),
            .number => |number| {
                if (!std.math.isFinite(number)) return self.walker.fail("non-finite number", .{});
                try data.writeFloat(out, number);
            },
            .string => |string| try self.writeEscaped(out, string.bytes()),
            .table => |table| if (!self.walker.isNull(table)) return self.walker.failValue(value),
            else => return self.walker.failValue(value),
        }
    }

    fn writeEscaped(self: *Writer, out: *std.Io.Writer, bytes: []const u8) !void {
        const specials = [_]u8{ self.options.delimiter, '"', '\r', '\n' };
        if (std.mem.indexOfAny(u8, bytes, &specials) == null) return out.writeAll(bytes);
        try out.writeByte('"');
        var rest = bytes;
        while (std.mem.indexOfScalar(u8, rest, '"')) |quote| {
            try out.writeAll(rest[0 .. quote + 1]);
            try out.writeByte('"');
            rest = rest[quote + 1 ..];
        }
        try out.writeAll(rest);
        try out.writeByte('"');
    }
};
