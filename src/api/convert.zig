const std = @import("std");
const reflection = @import("../reflection.zig");
const runtime = @import("../runtime.zig");
const errors = @import("errors.zig");
const handle = @import("handle.zig");
const userdata_mod = @import("userdata.zig");
const AnyUserdata = userdata_mod.AnyUserdata;
const decode_mod = @import("decode.zig");
const Coroutine = @import("coroutine.zig").Coroutine;
const ErrorRef = errors.ErrorRef;
const Function = @import("function.zig").Function;
const Ref = handle.Ref;
const State = @import("state.zig").State;
const Table = @import("table.zig").Table;
const Value = @import("value.zig").Value;
const index_mod = @import("../runtime/index.zig");
const callbacks = @import("callbacks.zig");
const namespace = @import("namespace.zig");

pub fn expectedLuaType(comptime T: type) []const u8 {
    if (T == Value or T == Ref or T == ErrorRef) return "value";
    if (T == Table) return "table";
    if (T == Function) return "function";
    if (T == Coroutine) return "thread";
    if (T == AnyUserdata or userdata_mod.isHandle(T)) return "userdata";

    return switch (@typeInfo(T)) {
        .bool => "boolean",
        .int, .comptime_int, .float, .comptime_float => "number",
        .optional => |optional| expectedLuaType(optional.child),
        .pointer => |pointer| switch (pointer.size) {
            .slice => if (pointer.child == u8) "string" else "value",
            .one => if (@typeInfo(pointer.child) == .@"struct") @typeName(pointer.child) else "value",
            else => "value",
        },
        else => "value",
    };
}

pub fn convertArgs(state: *State, args: anytype) ![]runtime.Value {
    const Args = @TypeOf(args);
    const info = @typeInfo(Args);
    if (info != .@"struct" or !info.@"struct".is_tuple) @compileError("calls require tuple arguments: .{ ... }");

    const fields = reflection.fieldNames(info.@"struct");
    const raw_args = try state.allocator().alloc(runtime.Value, fields.len);
    errdefer state.allocator().free(raw_args);
    inline for (fields, 0..) |_, index| raw_args[index] = try toRuntimeValue(state, args[index]);
    return raw_args;
}

pub fn toRuntimeValue(state: *State, value: anytype) !runtime.Value {
    return toRuntimeValueNamed(state, value, "?");
}

/// Like `toRuntimeValue`; `name` labels a Zig function in Lua error messages.
pub fn toRuntimeValueNamed(state: *State, value: anytype, name: []const u8) !runtime.Value {
    const T = @TypeOf(value);
    if (T == Value) return switch (value) {
        .nil => .nil,
        .boolean => |v| .{ .boolean = v },
        .integer => |v| .{ .integer = v },
        .number => |v| .{ .number = v },
        .string => |v| .{ .string = try state.raw_state.strings.intern(v) },
        .table => |v| toRuntimeValue(state, v),
        .function => |v| toRuntimeValue(state, v),
        .coroutine => |v| toRuntimeValue(state, v),
        .userdata => |v| toRuntimeValue(state, v),
    };
    if (T == Ref) {
        try handle.validate(value, state);
        return handle.rawValue(value);
    }
    if (comptime T == Table or T == Function or T == Coroutine or T == ErrorRef or T == AnyUserdata or userdata_mod.isHandle(T)) {
        try handle.validate(value.ref, state);
        return handle.rawValue(value.ref);
    }
    if (comptime decode_mod.hasToLua(T)) return toRuntimeValue(state, value.toLua());
    if (comptime decode_mod.isEnumArray(T)) return enumArrayToRuntimeValue(state, value);
    if (comptime decode_mod.isEnumSet(T)) return enumSetToRuntimeValue(state, value);

    return switch (@typeInfo(T)) {
        .null => .nil,
        .optional => if (value) |payload| toRuntimeValue(state, payload) else .nil,
        .bool => .{ .boolean = value },
        .int, .comptime_int => .{ .integer = std.math.cast(i64, value) orelse return error.IntegerOutOfRange },
        .float, .comptime_float => .{ .number = @floatCast(value) },
        .pointer => |pointer| pointerToRuntimeValue(state, value, pointer),
        .array => |array| if (array.child == u8)
            .{ .string = try state.raw_state.strings.intern(value[0..]) }
        else
            arrayToRuntimeValue(state, value[0..]),
        .vector => |vector| arrayToRuntimeValue(state, @as([vector.len]vector.child, value)[0..]),
        .@"struct" => |info| structToRuntimeValue(state, value, info),
        .@"enum" => .{ .string = try state.raw_state.strings.intern(std.enums.tagName(T, value) orelse return error.UnsupportedType) },
        .enum_literal => .{ .string = try state.raw_state.strings.intern(@tagName(value)) },
        .@"fn" => .{ .api_callback = try callbacks.intern(state, name, callbacks.typedHostFn(value)) },
        .type => namespaceToRuntimeValue(state, value, .{}),
        else => error.UnsupportedType,
    };
}

/// Whether `toRuntimeValue` accepts a `T`; pointers to structs are assumed convertible.
pub fn canConvert(comptime T: type) bool {
    if (T == Value or T == Ref or T == Table or T == Function or T == Coroutine or T == ErrorRef or T == AnyUserdata or userdata_mod.isHandle(T)) return true;
    if (decode_mod.hasToLua(T) or decode_mod.isEnumArray(T) or decode_mod.isEnumSet(T)) return true;
    return switch (@typeInfo(T)) {
        .null, .bool, .int, .comptime_int, .float, .comptime_float, .@"enum", .enum_literal, .@"fn", .type => true,
        .optional => |optional| canConvert(optional.child),
        .array => |array| array.child == u8 or canConvert(array.child),
        .vector => |vector| canConvert(vector.child),
        .pointer => |pointer| switch (pointer.size) {
            .slice => pointer.child == u8 or canConvert(pointer.child),
            .one => switch (@typeInfo(pointer.child)) {
                .array => |array| array.child == u8 or canConvert(array.child),
                .@"struct" => true,
                else => false,
            },
            else => false,
        },
        .@"struct" => {
            inline for (comptime reflection.fieldsOf(T)) |field| {
                if (!canConvert(@FieldType(T, field))) return false;
            }
            return true;
        },
        else => false,
    };
}

fn namespaceToRuntimeValue(state: *State, comptime T: type, comptime path: namespace.Path) !runtime.Value {
    const hash_hint = comptime namespace.tags(T).len + namespace.exports(T, path).len;
    const table = state.raw_state.newTableWithHints(0, hash_hint) catch |err| return errors.captureLuaError(state, err);
    try writeNamespace(state, TableSink{ .table = table }, T, path);
    return table;
}

fn writeNamespace(state: *State, sink: anytype, comptime T: type, comptime path: namespace.Path) !void {
    inline for (comptime namespace.tags(T)) |tag| {
        try sink.put(state, tag, .{ .string = try state.raw_state.strings.intern(tag) });
    }
    inline for (comptime namespace.exports(T, path)) |name| {
        const key = comptime namespace.declOptions(T, name).key;
        const decl = @field(T, name);
        const raw = if (@TypeOf(decl) == type)
            try namespaceToRuntimeValue(state, decl, comptime path.push(T, name))
        else
            try toRuntimeValueNamed(state, decl, key);
        try sink.put(state, key, raw);
    }
}

/// Receives entries for a fresh table.
pub const TableSink = struct {
    table: runtime.Value,

    pub fn put(self: TableSink, state: *State, key: []const u8, value: runtime.Value) !void {
        const raw_key = runtime.Value{ .string = try state.raw_state.strings.intern(key) };
        index_mod.setTableValue(&state.raw_state, self.table, raw_key, value) catch |err| return errors.captureLuaError(state, err);
    }
};

/// Converts the fields of struct `value`, or the tags and exported declarations of struct or enum
/// type `value`, and passes each Lua key and value to `sink.put(state, key, value)`.
pub fn writeEntries(state: *State, sink: anytype, value: anytype) !void {
    const T = @TypeOf(value);
    if (T == type) return writeNamespace(state, sink, value, .{});
    const info = switch (@typeInfo(T)) {
        .@"struct" => |info| info,
        else => @compileError("expected a struct, or a struct or enum type, found " ++ @typeName(T)),
    };
    if (info.is_tuple) @compileError("expected a struct with named fields, found a tuple");
    inline for (comptime reflection.fieldsOf(T)) |field| {
        const options = comptime decode_mod.fieldOptions(T, field);
        if (options.embed) {
            try writeEntries(state, sink, @field(value, field));
        } else {
            try sink.put(state, options.key, try toRuntimeValueNamed(state, @field(value, field), options.key));
        }
    }
}

fn enumArrayToRuntimeValue(state: *State, value: anytype) !runtime.Value {
    const T = @TypeOf(value);
    const table = state.raw_state.newTableWithHints(0, T.len) catch |err| return errors.captureLuaError(state, err);
    inline for (comptime reflection.fieldsOf(T.Key)) |name| {
        const raw_key = runtime.Value{ .string = try state.raw_state.strings.intern(name) };
        const raw_value = try toRuntimeValue(state, value.get(@field(T.Key, name)));
        index_mod.setTableValue(&state.raw_state, table, raw_key, raw_value) catch |err| return errors.captureLuaError(state, err);
    }
    return table;
}

fn enumSetToRuntimeValue(state: *State, value: anytype) !runtime.Value {
    const T = @TypeOf(value);
    const table = state.raw_state.newTableWithHints(@intCast(value.count()), 0) catch |err| return errors.captureLuaError(state, err);
    var next: i64 = 1;
    inline for (comptime reflection.fieldsOf(T.Key)) |name| {
        if (value.contains(@field(T.Key, name))) {
            const raw_name = runtime.Value{ .string = try state.raw_state.strings.intern(name) };
            index_mod.setTableValue(&state.raw_state, table, .{ .integer = next }, raw_name) catch |err| return errors.captureLuaError(state, err);
            next += 1;
        }
    }
    return table;
}

fn pointerToRuntimeValue(state: *State, value: anytype, comptime pointer: std.builtin.Type.Pointer) !runtime.Value {
    switch (pointer.size) {
        .slice => {
            if (pointer.child == u8) return .{ .string = try state.raw_state.strings.intern(value) };
            return arrayToRuntimeValue(state, value);
        },
        .one => switch (@typeInfo(pointer.child)) {
            .array => |array| {
                if (array.child == u8) return .{ .string = try state.raw_state.strings.intern(value[0..]) };
                return arrayToRuntimeValue(state, value[0..]);
            },
            .@"struct" => return toRuntimeValue(state, value.*),
            .@"fn" => @compileError("pass a function to Lua directly instead of through a pointer, or wrap the pointer with State.registerTyped"),
            else => return error.UnsupportedType,
        },
        else => return error.UnsupportedType,
    }
}

fn arrayToRuntimeValue(state: *State, values: anytype) !runtime.Value {
    const array_hint = std.math.cast(u32, values.len) orelse return error.IntegerOutOfRange;
    const table = state.raw_state.newTableWithHints(array_hint, 0) catch |err| return errors.captureLuaError(state, err);
    for (values, 0..) |item, index| {
        const raw_item = try toRuntimeValue(state, item);
        const raw_index: i64 = @intCast(index + 1);
        index_mod.setTableValue(&state.raw_state, table, .{ .integer = raw_index }, raw_item) catch |err| return errors.captureLuaError(state, err);
    }
    return table;
}

fn structToRuntimeValue(state: *State, value: anytype, comptime info: std.builtin.Type.Struct) !runtime.Value {
    if (info.is_tuple) return tupleToRuntimeValue(state, value, reflection.fieldNames(info).len);

    const hash_hint = std.math.cast(u32, reflection.fieldNames(info).len) orelse return error.IntegerOutOfRange;

    const table = state.raw_state.newTableWithHints(0, hash_hint) catch |err| return errors.captureLuaError(state, err);
    try writeEntries(state, TableSink{ .table = table }, value);
    return table;
}

fn tupleToRuntimeValue(state: *State, value: anytype, comptime len: usize) !runtime.Value {
    const array_hint = std.math.cast(u32, len) orelse return error.IntegerOutOfRange;
    const table = state.raw_state.newTableWithHints(array_hint, 0) catch |err| return errors.captureLuaError(state, err);
    inline for (0..len) |index| {
        const raw_item = try toRuntimeValue(state, value[index]);
        const raw_index: i64 = @intCast(index + 1);
        index_mod.setTableValue(&state.raw_state, table, .{ .integer = raw_index }, raw_item) catch |err| return errors.captureLuaError(state, err);
    }
    return table;
}

pub fn fromRuntimeResults(state: *State, results: []const runtime.Value, comptime R: type) !R {
    if (R == void) return {};
    if (comptime isTupleResult(R)) {
        var values: @Tuple(R.field_types) = undefined;
        var initialized: usize = 0;
        errdefer inline for (R.field_types, 0..) |Field, index| {
            if (index < initialized) deinitIfOwned(Field, &values[index]);
        };
        inline for (R.field_types, 0..) |Field, index| {
            const raw = if (index < results.len) results[index] else runtime.Value.nil;
            values[index] = try fromRuntimeValue(state, raw, Field);
            initialized += 1;
        }
        return .{ .values = values };
    }

    const raw = if (results.len == 0) runtime.Value.nil else results[0];
    return fromRuntimeValue(state, raw, R);
}

pub fn fromRuntimeValue(state: *State, raw: runtime.Value, comptime T: type) !T {
    if (T == Value) return valueFromRuntime(state, raw);
    if (T == Ref) return handle.fromRuntime(state, raw);
    if (T == Table) return if (raw == .table) rooted(Table, state, raw) else error.TypeMismatch;
    if (T == Function) return if (isFunction(raw)) rooted(Function, state, raw) else error.TypeMismatch;
    if (T == Coroutine) return if (raw == .thread) rooted(Coroutine, state, raw) else error.TypeMismatch;
    if (T == AnyUserdata) return if (raw == .userdata) rooted(AnyUserdata, state, raw) else error.TypeMismatch;
    if (comptime userdata_mod.isHandle(T)) return switch (raw) {
        .userdata => |userdata| if (userdata.type_id == userdata_mod.typeId(T.ValueType)) rooted(T, state, raw) else error.TypeMismatch,
        else => error.TypeMismatch,
    };
    if (T == void) return {};

    return switch (@typeInfo(T)) {
        .bool => switch (raw) {
            .boolean => |value| value,
            else => error.TypeMismatch,
        },
        .int, .comptime_int => switch (raw) {
            .integer => |value| std.math.cast(T, value) orelse return error.IntegerOutOfRange,
            .number => |value| if (integerFromFloat(value)) |integer|
                std.math.cast(T, integer) orelse return error.IntegerOutOfRange
            else
                error.TypeMismatch,
            else => error.TypeMismatch,
        },
        .float, .comptime_float => switch (raw) {
            .integer => |value| @as(T, @floatFromInt(value)),
            .number => |value| @as(T, @floatCast(value)),
            else => error.TypeMismatch,
        },
        .optional => |optional| if (raw == .nil)
            null
        else
            try fromRuntimeValue(state, raw, optional.child),
        .pointer => |pointer| switch (pointer.size) {
            .slice => if (pointer.child == u8) switch (raw) {
                .string => |value| value.bytes(),
                else => error.TypeMismatch,
            } else error.UnsupportedType,
            .one => if (@typeInfo(pointer.child) == .@"struct") switch (raw) {
                .userdata => |userdata| userdata_mod.payloadPtr(pointer.child, userdata),
                else => error.TypeMismatch,
            } else error.UnsupportedType,
            else => error.UnsupportedType,
        },
        else => error.UnsupportedType,
    };
}

fn valueFromRuntime(state: *State, raw: runtime.Value) !Value {
    return switch (raw) {
        .nil => .nil,
        .boolean => |boolean| .{ .boolean = boolean },
        .integer => |integer| .{ .integer = integer },
        .number => |number| .{ .number = number },
        .string => |string| .{ .string = string.bytes() },
        .table => .{ .table = try rooted(Table, state, raw) },
        .userdata => .{ .userdata = try rooted(AnyUserdata, state, raw) },
        .thread => .{ .coroutine = try rooted(Coroutine, state, raw) },
        else => .{ .function = try rooted(Function, state, raw) },
    };
}

fn isFunction(raw: runtime.Value) bool {
    return switch (raw) {
        .nil, .boolean, .integer, .number, .string, .table, .userdata, .thread => false,
        else => true,
    };
}

fn rooted(comptime H: type, state: *State, raw: runtime.Value) !H {
    return .{ .ref = try handle.fromRuntime(state, raw) };
}

pub fn integerFromFloat(value: f64) ?i64 {
    if (!std.math.isFinite(value)) return null;
    if (@trunc(value) != value) return null;
    if (value < @as(f64, @floatFromInt(std.math.minInt(i64))) or value >= @as(f64, @floatFromInt(std.math.maxInt(i64)))) return null;
    return @intFromFloat(value);
}

fn isTupleResult(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "is_zlua_tuple") and T.is_zlua_tuple,
        else => false,
    };
}

pub fn isOwnedApiValue(comptime T: type) bool {
    return isTupleResult(T) or T == Value or T == Ref or T == Table or T == Function or T == Coroutine or T == ErrorRef or T == AnyUserdata or userdata_mod.isHandle(T);
}

pub fn deinitIfOwned(comptime T: type, value: *T) void {
    if (comptime isOwnedApiValue(T)) {
        value.deinit();
    } else if (comptime @typeInfo(T) == .optional) {
        if (value.*) |*payload| deinitIfOwned(@typeInfo(T).optional.child, payload);
    }
}
