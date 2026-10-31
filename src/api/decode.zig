const std = @import("std");
const reflection = @import("../reflection.zig");
const convert = @import("convert.zig");
const Table = @import("table.zig").Table;
const Value = @import("value.zig").Value;
const Allocator = std.mem.Allocator;

pub const DecodeError = error{Invalid} || Allocator.Error;

/// The message of the first decoding failure.
pub const Diagnostic = struct {
    gpa: Allocator,
    /// Owned by `gpa`; empty until something fails.
    text: []u8 = &.{},

    pub fn deinit(self: *Diagnostic) void {
        self.gpa.free(self.text);
        self.text = &.{};
    }

    /// Records the message unless one is recorded already, and returns `error.Invalid`.
    pub fn fail(self: *Diagnostic, comptime fmt: []const u8, args: anytype) DecodeError {
        if (self.text.len == 0) self.text = try std.fmt.allocPrint(self.gpa, fmt, args);
        return error.Invalid;
    }

    /// The message, owned by `gpa`, leaving the diagnostic empty.
    pub fn take(self: *Diagnostic) []u8 {
        defer self.text = &.{};
        return self.text;
    }
};

/// How a struct field maps to a Lua table, from the struct's `lua` declaration.
pub const FieldOptions = struct {
    /// The Lua key, the field name by default.
    key: []const u8,
    /// Decoding fails when the key is absent.
    required: bool = false,
    /// A description for generated documentation.
    doc: []const u8 = "",
    /// The fields of this struct field are given inline in the outer table.
    embed: bool = false,
    /// The enum whose values a bit set field lists; each sets the bit of its integer value.
    elements: ?type = null,
};

/// The options of field `name` of `T`.
pub fn fieldOptions(comptime T: type, comptime name: []const u8) FieldOptions {
    comptime {
        @setEvalBranchQuota(100_000);
        var options: FieldOptions = .{ .key = name };
        if (@hasDecl(T, "lua") and @hasField(@TypeOf(T.lua), name)) {
            const declared = @field(T.lua, name);
            for (reflection.fieldsOf(@TypeOf(declared))) |option| {
                if (!@hasField(FieldOptions, option)) @compileError(@typeName(T) ++ ".lua." ++ name ++ ": unknown option " ++ option);
                @field(options, option) = @field(declared, option);
            }
        }
        return options;
    }
}

/// The Lua keys of the fields of `T`, with the fields of embedded structs in place of their own.
pub fn fieldKeys(comptime T: type) [keyCount(T)][]const u8 {
    const all = comptime blk: {
        @setEvalBranchQuota(100_000);
        var keys: [keyCount(T)][]const u8 = undefined;
        var count = 0;
        for (reflection.fieldsOf(T)) |name| {
            const options = fieldOptions(T, name);
            if (options.embed) {
                for (fieldKeys(@FieldType(T, name))) |key| {
                    keys[count] = key;
                    count += 1;
                }
            } else {
                keys[count] = options.key;
                count += 1;
            }
        }
        break :blk keys;
    };
    return all;
}

fn keyCount(comptime T: type) usize {
    comptime {
        @setEvalBranchQuota(100_000);
        var count = 0;
        for (reflection.fieldsOf(T)) |name| {
            count += if (fieldOptions(T, name).embed) keyCount(@FieldType(T, name)) else 1;
        }
        return count;
    }
}

pub fn isEnumArray(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "Key") and @hasDecl(T, "Value") and T == std.EnumArray(T.Key, T.Value);
}

pub fn isEnumSet(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "Key") and !@hasDecl(T, "Value") and T == std.EnumSet(T.Key);
}

fn isBitSet(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "MaskInt") and @hasDecl(T, "bit_length");
}

fn hasDeclaration(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

pub fn hasFromLua(comptime T: type) bool {
    return hasDeclaration(T, "fromLua");
}

pub fn hasToLua(comptime T: type) bool {
    return hasDeclaration(T, "toLua");
}

/// Whether a typed callback parameter of type `T` is read by `Context.decodeArg`.
pub fn needsDecoding(comptime T: type) bool {
    if (hasFromLua(T)) return true;
    return switch (@typeInfo(T)) {
        .@"enum", .array, .vector => true,
        .@"struct" => !convert.isOwnedApiValue(T),
        .pointer => |pointer| pointer.size == .slice and pointer.child != u8,
        else => false,
    };
}

/// The value a field of type `T` holds before decoding: struct defaults, otherwise zeros and empties.
pub fn defaultValue(comptime T: type) T {
    if (comptime isEnumArray(T)) return .initFill(defaultValue(T.Value));
    if (comptime isEnumSet(T)) return .empty;
    return switch (@typeInfo(T)) {
        .int, .float => 0,
        .bool => false,
        .optional => null,
        .@"enum" => |info| if (reflection.isExhaustive(info)) std.enums.values(T)[0] else @enumFromInt(0),
        .array => |array| @splat(defaultValue(array.child)),
        .vector => |vector| @splat(defaultValue(vector.child)),
        .pointer => &.{},
        .@"struct" => std.mem.zeroInit(T, .{}),
        else => @compileError("no default value for " ++ @typeName(T)),
    };
}

/// Reads Lua values into Zig values by their types, reporting the first failure with its path.
///
/// A type may declare `pub fn fromLua(d: anytype, value: Value, out: *T) DecodeError!void`.
/// `Context` may decide types it does not own with `pub fn decodes(comptime T: type) bool` and
/// `pub fn decode(d: anytype, comptime T: type, value: Value, out: *T) DecodeError!void`; it is
/// reachable as `d.context`.
pub fn Decoder(comptime Context: type) type {
    return struct {
        const Self = @This();

        /// Allocates the decoded strings and slices.
        allocator: Allocator,
        /// Receives the first failure, prefixed with the path; its `gpa` allocates `path`.
        diagnostic: *Diagnostic,
        context: Context,
        /// Levels below the current value whose struct fields and enum array entries must all be given.
        strict: u32 = 0,
        /// Match enum names ignoring case.
        ignore_enum_case: bool = false,
        /// Where the value being decoded is, as `.field[2].field`.
        path: std.ArrayList(u8) = .empty,

        pub fn deinit(self: *Self) void {
            self.path.deinit(self.diagnostic.gpa);
            self.path = .empty;
        }

        /// Records the first failure, prefixed with the path, and returns `error.Invalid`.
        pub fn fail(self: *Self, comptime fmt: []const u8, args: anytype) DecodeError {
            if (self.diagnostic.text.len > 0) return error.Invalid;
            const items = self.path.items;
            const path = if (items.len > 0 and items[0] == '.') items[1..] else items;
            if (path.len == 0) return self.diagnostic.fail(fmt, args);
            return self.diagnostic.fail("{s}: " ++ fmt, .{path} ++ args);
        }

        /// Appends a segment to the path; pass the result to `pop`.
        pub fn push(self: *Self, comptime fmt: []const u8, args: anytype) Allocator.Error!usize {
            const mark = self.path.items.len;
            try self.path.print(self.diagnostic.gpa, fmt, args);
            return mark;
        }

        pub fn pop(self: *Self, mark: usize) void {
            self.path.shrinkRetainingCapacity(mark);
        }

        /// Fails with the name of an embedding API error other than running out of memory.
        pub fn apiFail(self: *Self, err: anyerror) DecodeError {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.fail("{s}", .{@errorName(err)});
        }

        pub fn rawGet(self: *Self, table: Table, key: anytype) DecodeError!Value {
            return table.rawGet(key, Value) catch |err| self.apiFail(err);
        }

        pub fn rawLen(self: *Self, table: Table) DecodeError!usize {
            const length = table.rawLen() catch |err| return self.apiFail(err);
            return @intCast(@max(0, length));
        }

        /// The table `value`, or a failure when it isn't one.
        pub fn sequence(self: *Self, value: Value) DecodeError!Table {
            if (value != .table) return self.fail("expected a list, got {s}", .{value.typeName()});
            return value.table;
        }

        /// Decodes `value` into `out`.
        pub fn decode(self: *Self, comptime T: type, value: Value, out: *T) DecodeError!void {
            if (comptime @typeInfo(Context) == .@"struct" and @hasDecl(Context, "decodes") and Context.decodes(T)) return Context.decode(self, T, value, out);
            if (comptime hasFromLua(T)) return T.fromLua(self, value, out);
            if (comptime convert.isOwnedApiValue(T)) @compileError("can't decode into the handle type " ++ @typeName(T));
            if (comptime isEnumArray(T)) return self.decodeEnumArray(T, value, out);
            if (comptime isEnumSet(T)) return self.decodeEnumSet(T, value, out);
            if (comptime isBitSet(T)) @compileError(@typeName(T) ++ " needs `.elements` in its field's lua declaration");
            switch (@typeInfo(T)) {
                .int => out.* = try self.decodeInt(T, value),
                .float => out.* = switch (value) {
                    .integer => |integer| @floatFromInt(integer),
                    .number => |number| @floatCast(number),
                    else => return self.fail("expected a number, got {s}", .{value.typeName()}),
                },
                .bool => {
                    if (value != .boolean) return self.fail("expected a boolean, got {s}", .{value.typeName()});
                    out.* = value.boolean;
                },
                .@"enum" => out.* = try self.decodeEnum(T, value),
                .optional => |optional| {
                    if (value == .nil) return;
                    var inner: optional.child = defaultValue(optional.child);
                    try self.decode(optional.child, value, &inner);
                    out.* = inner;
                },
                .array => |array| {
                    const table = try self.sequence(value);
                    const length = try self.rawLen(table);
                    if (length != array.len) return self.fail("expected {d} values, got {d}", .{ array.len, length });
                    try self.decodeSequence(array.child, table, out);
                },
                .vector => |vector| {
                    var items: [vector.len]vector.child = undefined;
                    try self.decode([vector.len]vector.child, value, &items);
                    out.* = items;
                },
                .pointer => |pointer| {
                    if (pointer.size != .slice) @compileError("can't decode " ++ @typeName(T));
                    if (pointer.child == u8) {
                        if (value != .string) return self.fail("expected a string, got {s}", .{value.typeName()});
                        out.* = try self.allocator.dupe(u8, value.string);
                        return;
                    }
                    const table = try self.sequence(value);
                    const items = try self.allocator.alloc(pointer.child, try self.rawLen(table));
                    @memset(items, defaultValue(pointer.child));
                    out.* = items;
                    try self.decodeSequence(pointer.child, table, items);
                },
                .@"struct" => try self.decodeStruct(T, value, out, &.{}),
                else => @compileError("can't decode " ++ @typeName(T)),
            }
        }

        /// Decodes `value` with one strictness level fewer.
        pub fn decodeChild(self: *Self, comptime T: type, value: Value, out: *T) DecodeError!void {
            const strict = self.strict;
            self.strict -|= 1;
            defer self.strict = strict;
            return self.decode(T, value, out);
        }

        /// Decodes the table `value` into struct `out`; keys in `skip` are left for the caller.
        pub fn decodeStruct(self: *Self, comptime T: type, value: Value, out: *T, skip: []const []const u8) DecodeError!void {
            if (value != .table) return self.fail("expected a table, got {s}", .{value.typeName()});
            const keys = comptime fieldKeys(T);
            try self.checkKeys(value.table, &keys, skip);
            return self.decodeFields(T, value.table, out, skip);
        }

        /// Fails on a key of `table` that isn't a string among `keys` or `skip`.
        pub fn checkKeys(self: *Self, table: Table, keys: []const []const u8, skip: []const []const u8) DecodeError!void {
            var iterator = table.rawIterator() catch |err| return self.apiFail(err);
            defer iterator.deinit();
            while (iterator.next() catch |err| return self.apiFail(err)) |entry| {
                if (entry.key != .string) return self.fail("unexpected {s} key", .{entry.key.typeName()});
                if (!contains(keys, entry.key.string) and !contains(skip, entry.key.string)) {
                    return self.fail("unknown field \"{s}\"", .{entry.key.string});
                }
            }
        }

        /// Decodes a list of `E` values into the bit set `out`.
        pub fn decodeElements(self: *Self, comptime E: type, value: Value, out: anytype) DecodeError!void {
            const table = try self.sequence(value);
            out.* = .empty;
            for (0..try self.rawLen(table)) |index| {
                var item = try self.rawGet(table, @as(i64, @intCast(index + 1)));
                defer item.deinit();
                const mark = try self.push("[{d}]", .{index + 1});
                defer self.pop(mark);
                var element: E = defaultValue(E);
                try self.decode(E, item, &element);
                const bit: usize = @intFromEnum(element);
                if (bit >= @TypeOf(out.*).bit_length) return self.fail("{d} is out of range", .{bit});
                out.set(bit);
            }
        }

        fn decodeFields(self: *Self, comptime T: type, table: Table, out: *T, skip: []const []const u8) DecodeError!void {
            inline for (comptime reflection.fieldsOf(T)) |name| {
                const options = comptime fieldOptions(T, name);
                const Field = @FieldType(T, name);
                if (options.embed) {
                    try self.decodeFields(Field, table, &@field(out, name), skip);
                } else if (!contains(skip, options.key)) {
                    var item = try self.rawGet(table, options.key);
                    defer item.deinit();
                    const mark = try self.push(".{s}", .{options.key});
                    defer self.pop(mark);
                    if (item == .nil) {
                        if (self.strict > 0 or options.required) return self.fail("missing", .{});
                    } else if (options.elements) |Element| {
                        try self.decodeElements(Element, item, &@field(out, name));
                    } else {
                        try self.decodeChild(Field, item, &@field(out, name));
                    }
                }
            }
        }

        fn decodeInt(self: *Self, comptime T: type, value: Value) DecodeError!T {
            const integer = switch (value) {
                .integer => |integer| integer,
                .number => |number| std.math.lossyCast(i64, number),
                else => return self.fail("expected an integer, got {s}", .{value.typeName()}),
            };
            if (value == .number and @as(f64, @floatFromInt(integer)) != value.number) {
                return self.fail("number has no integer representation", .{});
            }
            return std.math.cast(T, integer) orelse self.fail("{d} is out of range", .{integer});
        }

        fn decodeEnum(self: *Self, comptime T: type, value: Value) DecodeError!T {
            if (!reflection.isExhaustive(@typeInfo(T).@"enum")) @compileError("can't decode the non-exhaustive enum " ++ @typeName(T) ++ " without a hook");
            if (value != .string) return self.fail("expected a name, got {s}", .{value.typeName()});
            inline for (comptime reflection.fieldsOf(T)) |name| {
                const same = if (self.ignore_enum_case) std.ascii.eqlIgnoreCase(name, value.string) else std.mem.eql(u8, name, value.string);
                if (same) return @field(T, name);
            }
            return self.fail("unknown name \"{s}\"; expected one of {s}", .{ value.string, comptime enumList(T) });
        }

        fn decodeEnumSet(self: *Self, comptime T: type, value: Value, out: *T) DecodeError!void {
            const table = try self.sequence(value);
            out.* = .empty;
            for (0..try self.rawLen(table)) |index| {
                var item = try self.rawGet(table, @as(i64, @intCast(index + 1)));
                defer item.deinit();
                const mark = try self.push("[{d}]", .{index + 1});
                defer self.pop(mark);
                out.insert(try self.decodeEnum(T.Key, item));
            }
        }

        fn decodeEnumArray(self: *Self, comptime T: type, value: Value, out: *T) DecodeError!void {
            if (value != .table) return self.fail("expected a table, got {s}", .{value.typeName()});
            const keys = comptime enumKeys(T.Key);
            try self.checkKeys(value.table, &keys, &.{});
            inline for (comptime reflection.fieldsOf(T.Key)) |name| {
                var item = try self.rawGet(value.table, name);
                defer item.deinit();
                const mark = try self.push(".{s}", .{name});
                defer self.pop(mark);
                if (item == .nil) {
                    if (self.strict > 0) return self.fail("missing", .{});
                } else {
                    try self.decodeChild(T.Value, item, out.getPtr(@field(T.Key, name)));
                }
            }
        }

        fn decodeSequence(self: *Self, comptime Element: type, table: Table, out: []Element) DecodeError!void {
            for (out, 0..) |*element, index| {
                var item = try self.rawGet(table, @as(i64, @intCast(index + 1)));
                defer item.deinit();
                const mark = try self.push("[{d}]", .{index + 1});
                defer self.pop(mark);
                try self.decode(Element, item, element);
            }
        }
    };
}

/// Options for `decode`.
pub const DecodeOptions = struct {
    /// Allocates the decoded strings and slices; a failed decode does not free them.
    allocator: Allocator,
    /// Receives the message of `error.Invalid`.
    diagnostic: *Diagnostic,
    /// Levels below the value whose struct fields and enum array entries must all be given.
    strict: u32 = 0,
    ignore_enum_case: bool = false,
};

/// Decodes `value` into a `T`, starting from `defaultValue(T)`.
pub fn decode(comptime T: type, value: Value, options: DecodeOptions) DecodeError!T {
    var decoder: Decoder(void) = .{
        .allocator = options.allocator,
        .diagnostic = options.diagnostic,
        .context = {},
        .strict = options.strict,
        .ignore_enum_case = options.ignore_enum_case,
    };
    defer decoder.deinit();
    var out = defaultValue(T);
    try decoder.decode(T, value, &out);
    return out;
}

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

fn enumKeys(comptime E: type) [reflection.fieldsOf(E).len][]const u8 {
    comptime {
        var keys: [reflection.fieldsOf(E).len][]const u8 = undefined;
        for (reflection.fieldsOf(E), 0..) |name, index| keys[index] = name;
        return keys;
    }
}

fn enumList(comptime E: type) []const u8 {
    comptime {
        var list: []const u8 = "";
        for (reflection.fieldsOf(E), 0..) |name, index| list = list ++ (if (index > 0) ", " else "") ++ name;
        return list;
    }
}
