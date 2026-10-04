//! Compile-time reflection shared by Zig 0.16 and 0.17.
const std = @import("std");
const Type = std.builtin.Type;

pub inline fn fieldNames(comptime info: anytype) []const [:0]const u8 {
    if (@hasField(@TypeOf(info), "field_names")) return info.field_names;
    const names = comptime blk: {
        var names: [info.fields.len][:0]const u8 = undefined;
        for (info.fields, 0..) |field, i| names[i] = field.name;
        break :blk names;
    };
    return &names;
}

pub inline fn fieldsOf(comptime T: type) []const [:0]const u8 {
    return switch (@typeInfo(T)) {
        inline .@"struct", .@"union", .@"enum" => |info| fieldNames(info),
        else => @compileError("expected struct, union, or enum"),
    };
}

pub inline fn declarationNames(comptime T: type) []const [:0]const u8 {
    const info = @typeInfo(T).@"struct";
    if (@hasField(Type.Struct, "decl_names")) return info.decl_names;
    const names = comptime blk: {
        var names: [info.decls.len][:0]const u8 = undefined;
        for (info.decls, 0..) |decl, i| names[i] = decl.name;
        break :blk names;
    };
    return &names;
}

pub inline fn paramTypes(comptime info: Type.Fn) []const ?type {
    if (@hasField(Type.Fn, "param_types")) return info.param_types;
    const types = comptime blk: {
        var types: [info.params.len]?type = undefined;
        for (info.params, 0..) |param, i| types[i] = param.type;
        break :blk types;
    };
    return &types;
}

pub inline fn isVariadic(comptime info: Type.Fn) bool {
    return if (@hasField(Type.Fn, "attrs")) info.attrs.varargs else info.is_var_args;
}

pub inline fn isConstPointer(comptime info: Type.Pointer) bool {
    return if (@hasField(Type.Pointer, "attrs")) info.attrs.@"const" else info.is_const;
}
