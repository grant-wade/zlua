const std = @import("std");
const reflection = @import("../reflection.zig");
const runtime = @import("../runtime.zig");
const runtime_types = @import("../runtime/types.zig");
const convert = @import("convert.zig");
const snapshot_mod = @import("snapshot.zig");
const userdata_mod = @import("userdata.zig");
const Context = @import("context.zig").Context;
const Function = @import("function.zig").Function;
const State = @import("state.zig").State;
const UserdataOptions = userdata_mod.UserdataOptions;

/// Untyped callback for `State.register`.
pub const HostFn = *const fn (ctx: *Context) anyerror!void;

pub const RegisteredCallback = struct {
    name: []const u8,
    callback: HostFn,
};

pub fn bindDispatch(state: *State) void {
    state.raw_state.setApiCallbackDispatch(apiCallbackDispatch, state);
}

pub fn create(state: *State, name: []const u8, callback: HostFn) !Function {
    try snapshot_mod.writableBindings(state);
    bindDispatch(state);
    const name_copy = try state.allocator().dupe(u8, name);
    errdefer state.allocator().free(name_copy);
    try state.callbacks.append(state.allocator(), .{ .name = name_copy, .callback = callback });
    errdefer _ = state.callbacks.pop();
    return convert.fromRuntimeValue(state, .{ .api_callback = state.callbacks.items.len }, Function);
}

pub fn deinitNames(state: *State, state_allocator: std.mem.Allocator) void {
    for (state.callbacks.items) |entry| state_allocator.free(entry.name);
}

fn apiCallbackDispatch(raw: *runtime.ApiCallbackContext) anyerror!void {
    const user_data = raw.user_data orelse return raw.raise(.{ .string = try raw.state.strings.intern("host callback state unavailable") });
    const state: *State = @ptrCast(@alignCast(user_data));
    if (raw.callback_id == 0 or raw.callback_id > state.callbacks.items.len) {
        return raw.raise(.{ .string = try raw.state.strings.intern("unknown host callback") });
    }

    const entry = state.callbacks.items[raw.callback_id - 1];
    raw.function_name = entry.name;
    var context = Context{ .lua = state, .raw = raw };
    try entry.callback(&context);
}

pub fn callTyped(comptime function: anytype, ctx: *Context) !void {
    const FunctionType = @TypeOf(function);
    const SignatureType = switch (@typeInfo(FunctionType)) {
        .@"fn" => FunctionType,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => pointer.child,
            else => @compileError("registerTyped requires a function or function pointer"),
        },
        else => @compileError("registerTyped requires a function or function pointer"),
    };
    const function_info = switch (@typeInfo(FunctionType)) {
        .@"fn" => |info| info,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => |info| info,
            else => @compileError("registerTyped requires a function or function pointer"),
        },
        else => @compileError("registerTyped requires a function or function pointer"),
    };

    if (reflection.isVariadic(function_info)) @compileError("registerTyped does not support varargs functions");

    var args: std.meta.ArgsTuple(SignatureType) = undefined;
    var scopes: ArgumentScopes(reflection.paramTypes(function_info).len) = .{};
    defer scopes.deinit(ctx);
    var lua_arg_index: usize = 0;
    inline for (reflection.paramTypes(function_info), 0..) |param, index| {
        const Param = param orelse @compileError("registerTyped requires typed parameters");
        if (Param == *Context) {
            args[index] = ctx;
        } else {
            args[index] = try scopes.arg(ctx, lua_arg_index, Param);
            lua_arg_index += 1;
        }
    }

    const Return = function_info.return_type orelse void;
    if (Return == void) {
        @call(.auto, function, args);
        try ctx.returnValues(.{});
        return;
    }

    switch (@typeInfo(Return)) {
        .error_union => |error_union| {
            if (comptime error_union.payload == void) {
                try @call(.auto, function, args);
                try ctx.returnValues(.{});
            } else {
                var result = try @call(.auto, function, args);
                defer convert.deinitIfOwned(error_union.payload, &result);
                try ctx.returnValues(result);
            }
        },
        else => {
            var result = @call(.auto, function, args);
            defer convert.deinitIfOwned(Return, &result);
            try ctx.returnValues(result);
        },
    }
}

pub fn callUserdataInitializer(comptime T: type, comptime initializer: anytype, comptime options: UserdataOptions(T), ctx: *Context) !void {
    const FunctionType = @TypeOf(initializer);
    const SignatureType = switch (@typeInfo(FunctionType)) {
        .@"fn" => FunctionType,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => pointer.child,
            else => @compileError("userdata initializers require a function or function pointer"),
        },
        else => @compileError("userdata initializers require a function or function pointer"),
    };
    const function_info = switch (@typeInfo(FunctionType)) {
        .@"fn" => |info| info,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => |info| info,
            else => @compileError("userdata initializers require a function or function pointer"),
        },
        else => @compileError("userdata initializers require a function or function pointer"),
    };

    if (reflection.isVariadic(function_info)) @compileError("userdata initializers do not support varargs functions");

    var args: std.meta.ArgsTuple(SignatureType) = undefined;
    var scopes: ArgumentScopes(reflection.paramTypes(function_info).len) = .{};
    defer scopes.deinit(ctx);
    var lua_arg_index: usize = 0;
    inline for (reflection.paramTypes(function_info), 0..) |param, index| {
        const Param = param orelse @compileError("userdata initializer parameters must be typed");
        if (Param == *Context) {
            args[index] = ctx;
        } else {
            args[index] = try scopes.arg(ctx, lua_arg_index, Param);
            lua_arg_index += 1;
        }
    }

    const Return = function_info.return_type orelse @compileError("userdata initializers must return T or !T");
    switch (@typeInfo(Return)) {
        .error_union => |error_union| {
            if (comptime error_union.payload != T) @compileError("userdata initializers must return T or !T");
            const value = try @call(.auto, initializer, args);
            var userdata = try ctx.state().newUserdataAuto(T, value, options);
            defer userdata.deinit();
            try ctx.returnValues(userdata);
        },
        else => {
            if (comptime Return != T) @compileError("userdata initializers must return T or !T");
            const value = @call(.auto, initializer, args);
            var userdata = try ctx.state().newUserdataAuto(T, value, options);
            defer userdata.deinit();
            try ctx.returnValues(userdata);
        },
    }
}

pub fn callUserdataMethod(comptime T: type, comptime function: anytype, ctx: *Context) !void {
    _ = userdata_mod.Userdata(T);
    const FunctionType = @TypeOf(function);
    const SignatureType = switch (@typeInfo(FunctionType)) {
        .@"fn" => FunctionType,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => pointer.child,
            else => @compileError("userdata methods require a function or function pointer"),
        },
        else => @compileError("userdata methods require a function or function pointer"),
    };
    const function_info = switch (@typeInfo(FunctionType)) {
        .@"fn" => |info| info,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => |info| info,
            else => @compileError("userdata methods require a function or function pointer"),
        },
        else => @compileError("userdata methods require a function or function pointer"),
    };

    if (reflection.isVariadic(function_info)) @compileError("userdata methods do not support varargs functions");
    if (reflection.paramTypes(function_info).len == 0) @compileError("userdata methods require a receiver parameter");
    const Receiver = reflection.paramTypes(function_info)[0] orelse @compileError("userdata method receiver must be typed");
    if (comptime !userdata_mod.isReceiver(T, Receiver)) @compileError("userdata method receiver must be *T or *const T");

    var args: std.meta.ArgsTuple(SignatureType) = undefined;
    var scopes: ArgumentScopes(reflection.paramTypes(function_info).len) = .{};
    defer scopes.deinit(ctx);
    args[0] = try scopes.arg(ctx, 0, Receiver);
    var lua_arg_index: usize = 1;
    inline for (reflection.paramTypes(function_info)[1..], 1..) |param, index| {
        const Param = param orelse @compileError("userdata method parameters must be typed");
        if (Param == *Context) {
            args[index] = ctx;
        } else {
            args[index] = try scopes.arg(ctx, lua_arg_index, Param);
            lua_arg_index += 1;
        }
    }

    const Return = function_info.return_type orelse void;
    if (Return == void) {
        @call(.auto, function, args);
        try ctx.returnValues(.{});
        return;
    }

    switch (@typeInfo(Return)) {
        .error_union => |error_union| {
            if (comptime error_union.payload == void) {
                try @call(.auto, function, args);
                try ctx.returnValues(.{});
            } else {
                var result = try @call(.auto, function, args);
                defer convert.deinitIfOwned(error_union.payload, &result);
                try ctx.returnValues(result);
            }
        },
        else => {
            var result = @call(.auto, function, args);
            defer convert.deinitIfOwned(Return, &result);
            try ctx.returnValues(result);
        },
    }
}

fn ArgumentScopes(comptime capacity: usize) type {
    return struct {
        entries: [capacity]runtime_types.UserdataScope = undefined,
        len: usize = 0,
        fn deinit(self: *@This(), ctx: *Context) void {
            if (comptime capacity == 0) return;
            while (self.len != 0) {
                self.len -= 1;
                userdata_mod.endScope(&ctx.lua.raw_state, &self.entries[self.len]);
            }
        }
        fn arg(self: *@This(), ctx: *Context, index: usize, comptime T: type) !T {
            const raw = ctx.raw.callbackArgValue(index);
            if (comptime @typeInfo(T) == .optional) {
                if (raw == .nil) return null;
                return try self.arg(ctx, index, @typeInfo(T).optional.child);
            }
            if (comptime @typeInfo(T) == .pointer) {
                const pointer = @typeInfo(T).pointer;
                if (comptime pointer.size == .one and @typeInfo(pointer.child) == .@"struct") {
                    if (raw == .userdata and raw.userdata.type_id == userdata_mod.typeId(pointer.child)) {
                        if (raw.userdata.payload) |p| if (p.snapshot_tracking == .scoped) {
                            try userdata_mod.beginScope(&ctx.lua.raw_state, &self.entries[self.len], raw.userdata, reflection.isConstPointer(pointer));
                            self.len += 1;
                        };
                        return @ptrCast(@alignCast(raw.userdata.ptr));
                    }
                }
            }
            return ctx.arg(index, T);
        }
    };
}
