const std = @import("std");
const reflection = @import("../reflection.zig");
const runtime = @import("../runtime.zig");
const errors = @import("errors.zig");
const handle = @import("handle.zig");
const userdata_mod = @import("userdata.zig");
const AnyUserdata = userdata_mod.AnyUserdata;
const Coroutine = @import("coroutine.zig").Coroutine;
const ErrorRef = errors.ErrorRef;
const Function = @import("function.zig").Function;
const Ref = handle.Ref;
const State = @import("state.zig").State;
const Table = @import("table.zig").Table;
const Value = @import("value.zig").Value;
const index_mod = @import("../runtime/index.zig");

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
        .unsupported => error.UnsupportedType,
    };
    if (T == Ref) {
        try handle.validate(value, state);
        return handle.rawValue(value);
    }
    if (comptime T == Table or T == Function or T == Coroutine or T == ErrorRef or T == AnyUserdata or userdata_mod.isHandle(T)) {
        try handle.validate(value.ref, state);
        return handle.rawValue(value.ref);
    }

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
        .@"struct" => |info| structToRuntimeValue(state, value, info),
        else => error.UnsupportedType,
    };
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
    inline for (reflection.fieldNames(info)) |field| {
        const raw_key = runtime.Value{ .string = try state.raw_state.strings.intern(field) };
        const raw_value = try toRuntimeValue(state, @field(value, field));
        index_mod.setTableValue(&state.raw_state, table, raw_key, raw_value) catch |err| return errors.captureLuaError(state, err);
    }
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
    if (T == Function) return if (raw == .closure or raw == .api_callback) rooted(Function, state, raw) else error.TypeMismatch;
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
                .string => |value| value,
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
        .string => |string| .{ .string = string },
        .table => .{ .table = try rooted(Table, state, raw) },
        .closure, .api_callback => .{ .function = try rooted(Function, state, raw) },
        .userdata => .{ .userdata = try rooted(AnyUserdata, state, raw) },
        .thread => .{ .coroutine = try rooted(Coroutine, state, raw) },
        else => .unsupported,
    };
}

fn rooted(comptime H: type, state: *State, raw: runtime.Value) !H {
    return .{ .ref = try handle.fromRuntime(state, raw) };
}

fn integerFromFloat(value: f64) ?i64 {
    if (!std.math.isFinite(value)) return null;
    if (@trunc(value) != value) return null;
    if (value < @as(f64, @floatFromInt(std.math.minInt(i64))) or value > @as(f64, @floatFromInt(std.math.maxInt(i64)))) return null;
    return @intFromFloat(value);
}

fn isTupleResult(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "is_zlua_tuple") and T.is_zlua_tuple,
        else => false,
    };
}

fn isOwnedApiValue(comptime T: type) bool {
    return T == Value or T == Ref or T == Table or T == Function or T == Coroutine or T == ErrorRef or T == AnyUserdata or userdata_mod.isHandle(T);
}

pub fn deinitIfOwned(comptime T: type, value: *T) void {
    if (comptime isOwnedApiValue(T) or isTupleResult(T)) {
        value.deinit();
    } else if (comptime @typeInfo(T) == .optional) {
        if (value.*) |*payload| deinitIfOwned(@typeInfo(T).optional.child, payload);
    }
}
