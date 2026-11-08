const std = @import("std");
const cost = @import("../runtime/budget.zig").cost;
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const io = @import("io.zig");
const datetime = @import("datetime.zig");
const metatable_mod = @import("../runtime/metatable.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Table = runtime.Table;
const String = @import("../runtime/types.zig").String;

pub const max_depth = 64;

const max_table_len: usize = @min(std.math.maxInt(usize), std.math.maxInt(i64));

pub fn ensureSupportTables(state: *State) !void {
    const tables = &state.library_tables;
    if (tables.get(.data_null) == null) {
        const null_value = try state.newTableWithHints(0, 0);
        const null_metatable = try supportMetatable(state, "null");
        try metatable_mod.setTableMetatableRaw(state, null_value.table, null_metatable);
        tables.set(.data_null, null_value.table);
    }
    if (tables.get(.data_array_metatable) == null) tables.set(.data_array_metatable, try supportMetatable(state, "array"));
    if (tables.get(.data_object_metatable) == null) tables.set(.data_object_metatable, try supportMetatable(state, "object"));
}

pub fn nullValue(state: *State) !Value {
    try ensureSupportTables(state);
    return .{ .table = state.library_tables.get(.data_null).? };
}

fn supportMetatable(state: *State, name: []const u8) !*Table {
    const value = try state.newTableWithHints(0, 2);
    const table = value.table;
    try state.setTableRaw(table, .{ .string = try state.strings.intern("__metatable") }, .{ .boolean = false });
    try state.setTableRaw(table, .{ .string = try state.strings.intern("__name") }, .{ .string = try state.strings.intern(name) });
    return table;
}

/// A MessagePack extension value that is not a timestamp.
pub const Extension = struct {
    type_id: i8,
    data: []const u8,
};

fn extensionMetatable(state: *State) !*Table {
    const tables = &state.library_tables;
    if (tables.get(.data_extension_metatable)) |existing| return existing;
    const created = try supportMetatable(state, "extension");
    tables.set(.data_extension_metatable, created);
    return created;
}

pub fn newExtension(state: *State, extension: Extension) !Value {
    const metatable = try extensionMetatable(state);
    const table = (try state.newTableWithHints(0, 2)).table;
    try metatable_mod.setTableMetatableRaw(state, table, metatable);
    try state.setTableRaw(table, .{ .string = try state.strings.intern("type") }, .{ .integer = extension.type_id });
    try state.setTableRaw(table, .{ .string = try state.strings.intern("data") }, .{ .string = try state.strings.intern(extension.data) });
    return .{ .table = table };
}

/// Peak bytes a reader allocates per input byte, for the format that needs the most.
const reader_peak_factor = 6;

pub fn inputBytes(state: *State, value: Value, function_name: []const u8) ![]const u8 {
    const bytes = try readInput(state, value, function_name);
    try state.budget.charge(cost.scanned(bytes.len));
    if (state.current_thread) |thread| try state.gc.reserve(thread, bytes.len *| reader_peak_factor);
    return bytes;
}

fn readInput(state: *State, value: Value, function_name: []const u8) ![]const u8 {
    return switch (value) {
        .string => |string| string.bytes(),
        else => if (io.checkedFile(state, value) != null) {
            const file = io.fileOf(value).?;
            if (file.closed) return state.failArgumentMessage(function_name, 1, "closed file");
            if (!file.readable) return state.failArgumentMessage(function_name, 1, "file is not readable");
            return io.readRemaining(state, value.userdata);
        } else state.failArgumentType(function_name, 1, "string or FILE*", value),
    };
}

/// Returns the options table at argument 2, or null when it is absent or nil.
pub fn optionsTable(state: *State, thread: *Thread, op: bytecode.Call, operation: []const u8) !?*Table {
    if (op.arg_count < 2) return null;
    const value = runtime.argValue(state, thread, op, 1);
    return switch (value) {
        .nil => null,
        .table => |table| table,
        else => state.failArgumentType(operation, 2, "table", value),
    };
}

/// Returns the string option `name` matched against `choices`, or null when it is unset.
/// Each choice maps its accepted spellings to a result.
pub fn enumOption(
    state: *State,
    table: *Table,
    operation: []const u8,
    comptime name: []const u8,
    comptime T: type,
    comptime choices: []const struct { []const []const u8, T },
    comptime invalid: []const u8,
) !?T {
    const value = table.getLiteral(name);
    if (value == .nil) return null;
    const bytes = switch (value) {
        .string => |string| string.bytes(),
        else => return state.failArgumentType(operation, 2, "table with string " ++ name, value),
    };
    inline for (choices) |choice| {
        for (choice[0]) |spelling| if (std.mem.eql(u8, bytes, spelling)) return choice[1];
    }
    return state.failArgumentMessage(operation, 2, invalid);
}

pub fn boolOption(state: *State, table: *Table, operation: []const u8, comptime name: []const u8) !?bool {
    const value = table.getLiteral(name);
    return switch (value) {
        .nil => null,
        .boolean => |boolean| boolean,
        else => state.failArgumentType(operation, 2, "table with boolean " ++ name, value),
    };
}

pub fn fail(state: *State, operation: []const u8, comptime fmt: []const u8, args: anytype) runtime.RuntimeError {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(state.allocator);
    runtime.appendFmt(state.allocator, &out, "{s}: " ++ fmt, .{operation} ++ args) catch return state.fail(operation);
    return state.fail(out.items);
}

/// Fails with the 1-based line and column of byte `offset` in `input`.
pub fn failAtLine(state: *State, operation: []const u8, input: []const u8, offset: usize, comptime fmt: []const u8, args: anytype) runtime.RuntimeError {
    const end = @min(offset, input.len);
    var line: usize = 1;
    var line_start: usize = 0;
    for (input[0..end], 0..) |byte, index| {
        if (byte == '\n') {
            line += 1;
            line_start = index + 1;
        }
    }
    return fail(state, operation, "line {d}, column {d}: " ++ fmt, .{ line, end - line_start + 1 } ++ args);
}

pub fn failAtByte(state: *State, operation: []const u8, offset: usize, comptime fmt: []const u8, args: anytype) runtime.RuntimeError {
    return fail(state, operation, "byte {d}: " ++ fmt, .{offset} ++ args);
}

/// Formats one input byte for an error message.
pub const ByteText = struct {
    byte: u8,

    pub fn format(self: ByteText, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (std.ascii.isPrint(self.byte) and self.byte != '\'') return writer.print("'{c}'", .{self.byte});
        return writer.print("byte 0x{x:0>2}", .{self.byte});
    }
};

/// Builds Lua tables from a stream of decoded values.
pub const Builder = struct {
    pub const Kind = enum { array, object };

    pub const Frame = struct {
        kind: Kind,
        table: *Table,
        next_index: i64 = 1,
        key: ?*const String = null,
        /// Values or key/value pairs still expected, for formats with counted containers.
        remaining: usize = 0,
    };

    state: *State,
    stack: std.ArrayList(Frame) = .empty,
    root: Value = .nil,
    has_root: bool = false,

    pub fn init(state: *State) Builder {
        return .{ .state = state };
    }

    pub fn deinit(self: *Builder) void {
        self.stack.deinit(self.state.allocator);
    }

    pub fn depth(self: *const Builder) usize {
        return self.stack.items.len;
    }

    pub fn top(self: *Builder) *Frame {
        return &self.stack.items[self.stack.items.len - 1];
    }

    /// `hint` is the expected number of entries.
    pub fn begin(self: *Builder, kind: Kind, hint: usize) !void {
        try ensureSupportTables(self.state);
        try self.stack.ensureUnusedCapacity(self.state.allocator, 1);
        const count = std.math.cast(u32, hint) orelse std.math.maxInt(u32);
        const value = switch (kind) {
            .array => try self.state.newTableWithHints(count, 0),
            .object => try self.state.newTableWithHints(0, count),
        };
        const metatable = switch (kind) {
            .array => self.state.library_tables.get(.data_array_metatable).?,
            .object => self.state.library_tables.get(.data_object_metatable).?,
        };
        try metatable_mod.setTableMetatableRaw(self.state, value.table, metatable);
        self.stack.appendAssumeCapacity(.{ .kind = kind, .table = value.table });
    }

    pub fn setKey(self: *Builder, key: []const u8) !void {
        self.top().key = try self.state.strings.intern(key);
    }

    pub fn end(self: *Builder) !void {
        const frame = self.stack.pop().?;
        try self.append(.{ .table = frame.table });
    }

    pub fn append(self: *Builder, value: Value) !void {
        try self.state.budget.charge(4);
        if (self.stack.items.len == 0) {
            self.root = value;
            self.has_root = true;
            return;
        }
        const frame = self.top();
        switch (frame.kind) {
            .array => {
                try self.state.setTableRaw(frame.table, .{ .integer = frame.next_index }, value);
                frame.next_index += 1;
            },
            .object => {
                try self.state.setTableRaw(frame.table, .{ .string = frame.key.? }, value);
                frame.key = null;
            },
        }
    }

    pub fn appendString(self: *Builder, bytes: []const u8) !void {
        try self.append(.{ .string = try self.state.strings.intern(bytes) });
    }

    pub fn appendNull(self: *Builder) !void {
        try self.append(try nullValue(self.state));
    }
};

/// How a writer encodes a Lua table.
pub const Shape = union(enum) {
    null,
    array: usize,
    object: usize,
    datetime: datetime.DateTime,
    extension: Extension,
};

/// One step from a table to the value being written, for error messages.
pub const PathStep = union(enum) {
    none,
    index: usize,
    key: []const u8,
};

/// Walks Lua values for a writer, rejecting cycles and deep nesting.
pub const Walker = struct {
    state: *State,
    operation: []const u8,
    tables: [max_depth]*Table = undefined,
    steps: [max_depth]PathStep = undefined,
    depth: usize = 0,

    pub fn init(state: *State, operation: []const u8) Walker {
        return .{ .state = state, .operation = operation };
    }

    /// Call once per value written.
    pub fn visit(self: *Walker, value: Value) !void {
        try self.state.budget.charge(4);
        if (value == .string) {
            if (self.state.current_thread) |thread| try self.state.gc.reserve(thread, value.string.len *| 3);
        }
    }

    pub fn isNull(self: *Walker, table: *Table) bool {
        return self.state.library_tables.get(.data_null) == table;
    }

    /// Classifies `table` and pushes it when it is an array or object. Pair each
    /// array or object result with `leave`.
    pub fn enter(self: *Walker, table: *Table) !Shape {
        const shape = try self.classify(table);
        if (shape != .array and shape != .object) return shape;
        for (self.tables[0..self.depth]) |open| {
            if (open == table) return self.fail("cyclic table", .{});
        }
        if (self.depth == max_depth) return self.fail("nesting deeper than {d} levels", .{max_depth});
        self.tables[self.depth] = table;
        self.steps[self.depth] = .none;
        self.depth += 1;
        return shape;
    }

    pub fn leave(self: *Walker) void {
        self.depth -= 1;
    }

    /// Records which child of the innermost open table is being written.
    pub fn step(self: *Walker, child: PathStep) void {
        self.steps[self.depth - 1] = child;
    }

    pub fn classify(self: *Walker, table: *Table) !Shape {
        if (self.isNull(table)) return .null;
        const tables = &self.state.library_tables;
        if (table.metatable != null) {
            if (table.metatable == tables.get(.data_datetime_metatable)) return switch (datetime.fromTable(table)) {
                .ok => |value| .{ .datetime = value },
                .invalid => |message| self.fail("invalid datetime: {s}", .{message}),
            };
            if (table.metatable == tables.get(.data_extension_metatable)) return .{ .extension = try self.extensionOf(table) };
        }
        const shape = tableShape(table);
        if (table.metatable != null and table.metatable == tables.get(.data_array_metatable)) return .{ .array = try self.arrayLen(shape) };
        if (table.metatable != null and table.metatable == tables.get(.data_object_metatable)) return .{ .object = try self.objectFieldCount(shape) };
        if (shape.other_count != 0) return self.fail("table has keys that are neither strings nor array indices", .{});
        if (shape.integer_count != 0 and shape.string_count != 0) return self.fail("table mixes array and object keys", .{});
        if (shape.integer_count != 0) return .{ .array = try self.arrayLen(shape) };
        return .{ .object = shape.string_count };
    }

    fn extensionOf(self: *Walker, table: *Table) !Extension {
        const type_id = table.getLiteral("type");
        const integer = runtime.toInteger(type_id) orelse return self.fail("extension type must be an integer", .{});
        const data = table.getLiteral("data");
        if (data != .string) return self.fail("extension data must be a string", .{});
        return .{ .type_id = std.math.cast(i8, integer) orelse return self.fail("extension type must be between -128 and 127", .{}), .data = data.string.bytes() };
    }

    fn arrayLen(self: *Walker, shape: TableShape) !usize {
        if (shape.string_count != 0 or shape.other_count != 0) return self.fail("table mixes array and object keys", .{});
        if (shape.max_index > max_table_len) return self.fail("array too large", .{});
        if (shape.integer_count != shape.max_index) return self.fail("array contains nil hole", .{});
        return shape.max_index;
    }

    fn objectFieldCount(self: *Walker, shape: TableShape) !usize {
        if (shape.integer_count != 0 or shape.other_count != 0) return self.fail("object keys must be strings", .{});
        return shape.string_count;
    }

    pub fn fail(self: *Walker, comptime fmt: []const u8, args: anytype) runtime.RuntimeError {
        if (self.depth == 0) return data_fail(self.state, self.operation, fmt, args);
        return data_fail(self.state, self.operation, "at {f}: " ++ fmt, .{PathText{ .steps = self.steps[0..self.depth] }} ++ args);
    }

    pub fn failValue(self: *Walker, value: Value) runtime.RuntimeError {
        return self.fail("cannot encode a {s} value", .{metatable_mod.luaTypeNameForError(self.state, value)});
    }
};

const data_fail = fail;

const PathText = struct {
    steps: []const PathStep,

    pub fn format(self: PathText, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeByte('$');
        for (self.steps) |item| switch (item) {
            .none => {},
            .index => |index| try writer.print("[{d}]", .{index}),
            .key => |key| if (isIdentifier(key)) {
                try writer.print(".{s}", .{key});
            } else {
                try writer.writeAll("[\"");
                for (key) |byte| {
                    if (byte == '"' or byte == '\\') try writer.writeByte('\\');
                    if (std.ascii.isPrint(byte)) try writer.writeByte(byte) else try writer.print("\\x{x:0>2}", .{byte});
                }
                try writer.writeAll("\"]");
            },
        };
    }

    fn isIdentifier(key: []const u8) bool {
        if (key.len == 0 or std.ascii.isDigit(key[0])) return false;
        for (key) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
        return true;
    }
};

const TableShape = struct {
    integer_count: usize = 0,
    max_index: usize = 0,
    string_count: usize = 0,
    other_count: usize = 0,
};

fn tableShape(table: *Table) TableShape {
    var shape: TableShape = .{};
    for (table.array.items(), 0..) |value, index| {
        if (value == .nil) continue;
        shape.integer_count += 1;
        shape.max_index = @max(shape.max_index, index + 1);
    }
    for (table.entries()) |entry| {
        if (entry.value == .nil) continue;
        if (positiveIntegerIndex(entry.key)) |index| {
            shape.integer_count += 1;
            shape.max_index = @max(shape.max_index, index);
        } else if (entry.key == .string) {
            shape.string_count += 1;
        } else {
            shape.other_count += 1;
        }
    }
    return shape;
}

fn positiveIntegerIndex(value: Value) ?usize {
    const integer = switch (value) {
        .integer => |integer| integer,
        .number => |number| runtime.floatToInteger(number) orelse return null,
        else => return null,
    };
    if (integer <= 0) return null;
    return std.math.cast(usize, integer);
}

/// `value` must be finite. The text always has a fraction or an exponent.
pub fn writeFloat(writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    const magnitude = @abs(value);
    if (magnitude != 0 and (magnitude >= 1e15 or magnitude < 1e-5)) return writer.print("{e}", .{value});
    try writer.print("{d}", .{value});
    if (value == @trunc(value)) try writer.writeAll(".0");
}

/// Runs `encode(context, writer)` into a fresh buffer and returns the result as a Lua string.
pub fn returnEncoded(state: *State, thread: *Thread, op: bytecode.Call, operation: []const u8, context: anytype, comptime encode: anytype) (runtime.RuntimeError || error{Interrupted})!void {
    var out = std.Io.Writer.Allocating.init(state.allocator);
    defer out.deinit();
    encode(context, &out.writer) catch |err| switch (err) {
        error.WriteFailed, error.OutOfMemory => return error.OutOfMemory,
        error.RuntimeError => return error.RuntimeError,
        error.StackOverflow => return error.StackOverflow,
        error.UnsupportedOpcode => return error.UnsupportedOpcode,
        error.Interrupted => return error.Interrupted,
        else => return fail(state, operation, "{s}", .{@errorName(err)}),
    };
    const bytes = try out.toOwnedSlice();
    defer state.allocator.free(bytes);
    const string = try state.strings.intern(bytes);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = string }});
}

pub fn returnValue(state: *State, thread: *Thread, op: bytecode.Call, value: Value) !void {
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}
