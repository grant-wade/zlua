//! Which public declarations of a struct or enum type convert to Lua, and under which keys.
const std = @import("std");
const reflection = @import("../reflection.zig");
const callbacks = @import("callbacks.zig");
const convert = @import("convert.zig");

/// How a public declaration maps to a Lua table, from the namespace's `lua` declaration.
pub const DeclOptions = struct {
    /// The Lua key, the declaration name by default.
    key: []const u8,
    /// Leaves the declaration out.
    skip: bool = false,
};

/// The namespaces enclosing the one being converted, outermost first, and the declarations
/// that lead to it.
pub const Path = struct {
    types: []const type = &.{},
    names: []const []const u8 = &.{},

    pub fn push(comptime self: Path, comptime T: type, comptime name: []const u8) Path {
        return .{ .types = self.types ++ .{T}, .names = self.names ++ .{name} };
    }

    fn contains(comptime self: Path, comptime T: type) bool {
        for (self.types) |Outer| if (Outer == T) return true;
        return false;
    }
};

pub fn declOptions(comptime T: type, comptime name: []const u8) DeclOptions {
    comptime {
        var options: DeclOptions = .{ .key = name };
        if (@hasDecl(T, "lua") and @hasField(@TypeOf(T.lua), name)) {
            const declared = @field(T.lua, name);
            for (reflection.fieldsOf(@TypeOf(declared))) |option| {
                if (!@hasField(DeclOptions, option)) @compileError(@typeName(T) ++ ".lua." ++ name ++ ": unknown option " ++ option);
                @field(options, option) = @field(declared, option);
            }
        }
        return options;
    }
}

/// Whether type `T` converts to a Lua table of its declarations, and of its tags for an enum.
pub fn isNamespace(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum" => true,
        else => false,
    };
}

/// The public declarations of `T` that convert to Lua when `T` is reached through `path`.
pub fn exports(comptime T: type, comptime path: Path) []const [:0]const u8 {
    comptime {
        if (!isNamespace(T)) @compileError("only struct and enum types convert to Lua, as tables of their public declarations; " ++ @typeName(T) ++ " is neither");
        @setEvalBranchQuota(1_000_000);
        var names: []const [:0]const u8 = &.{};
        for (reflection.declarationNames(T)) |name| {
            if (isExported(T, name, path)) names = names ++ .{name};
        }
        return names;
    }
}

/// The enum tags of `T`, or none for a struct.
pub fn tags(comptime T: type) []const [:0]const u8 {
    return if (@typeInfo(T) == .@"enum") reflection.fieldsOf(T) else &.{};
}

fn isExported(comptime T: type, comptime name: [:0]const u8, comptime path: Path) bool {
    if (std.mem.eql(u8, name, "lua") or declOptions(T, name).skip) return false;
    const Decl = @TypeOf(@field(T, name));
    if (Decl == type) {
        const Nested = @field(T, name);
        if (!isNamespace(Nested) or Nested == T or path.contains(Nested)) return false;
        return tags(Nested).len != 0 or exports(Nested, path.push(T, name)).len != 0;
    }
    const subject = comptime describe(T, name, path);
    switch (@typeInfo(Decl)) {
        .@"fn" => |info| {
            if (info.is_generic) @compileError(subject ++ " is generic and cannot be called from Lua" ++ skipHint(T, name, path));
            for (reflection.paramTypes(info)) |Param| {
                if (!callbacks.canReadParam(Param.?)) @compileError(subject ++ " takes a " ++ @typeName(Param.?) ++ ", which Lua cannot pass" ++ skipHint(T, name, path));
            }
            const Return = info.return_type.?;
            const Payload = switch (@typeInfo(Return)) {
                .error_union => |error_union| error_union.payload,
                else => Return,
            };
            if (Payload != void and !convert.canConvert(Payload)) @compileError(subject ++ " returns a " ++ @typeName(Payload) ++ ", which has no Lua value" ++ skipHint(T, name, path));
        },
        else => if (!convert.canConvert(Decl)) @compileError(subject ++ " has no Lua value" ++ skipHint(T, name, path)),
    }
    return true;
}

fn describe(comptime T: type, comptime name: []const u8, comptime path: Path) []const u8 {
    if (path.types.len == 0) return @typeName(T) ++ "." ++ name;
    var subject: []const u8 = @typeName(path.types[0]);
    for (path.names) |step| subject = subject ++ "." ++ step;
    return subject ++ "." ++ name;
}

fn skipHint(comptime T: type, comptime name: []const u8, comptime path: Path) []const u8 {
    const own = "; leave it out with `pub const lua = .{ ." ++ name ++ " = .{ .skip = true } }` in " ++ @typeName(T);
    if (path.types.len == 0) return own;
    return own ++ ", or leave out `" ++ path.names[0] ++ "` the same way in " ++ @typeName(path.types[0]);
}
