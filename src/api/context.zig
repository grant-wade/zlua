const std = @import("std");
const reflection = @import("../reflection.zig");
const runtime = @import("../runtime.zig");
const coroutine_runtime = @import("../runtime/coroutine.zig");
const callbacks = @import("callbacks.zig");
const convert = @import("convert.zig");
const handle = @import("handle.zig");
const Coroutine = @import("coroutine.zig").Coroutine;
const Function = @import("function.zig").Function;
const State = @import("state.zig").State;
const userdata_mod = @import("userdata.zig");
const call_mod = @import("../runtime/call.zig");

/// A typed callback parameter that receives the `T` given to `State.setHost` and takes no Lua
/// argument. The callback raises a Lua error when the state has no such pointer.
pub fn Host(comptime T: type) type {
    return struct {
        /// Marker for zlua's compile-time conversions.
        pub const is_zlua_host = true;
        pub const ValueType = T;

        ptr: *T,
    };
}

pub fn isHost(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "is_zlua_host") and T.is_zlua_host;
}

/// Callback context for functions registered with `State.register`.
pub const Context = struct {
    lua: *State,
    raw: *runtime.ApiCallbackContext,

    pub fn state(self: *Context) *State {
        return self.lua;
    }

    /// The `IoCapability.runtime` the state was created with, or null when none was configured.
    pub fn io(self: *Context) ?std.Io {
        return self.raw.state.options.io;
    }

    /// The pointer given to `State.setHost` when it points to a `T`, or null.
    pub fn host(self: *Context, comptime T: type) ?*T {
        return self.lua.host(T);
    }

    /// The name this callback was registered under.
    pub fn functionName(self: *Context) []const u8 {
        return self.raw.function_name;
    }

    pub fn argCount(self: *Context) usize {
        return self.raw.argCount();
    }

    /// A `[]const u8` argument borrows VM memory until the callback returns.
    pub fn arg(self: *Context, index: usize, comptime T: type) !T {
        const raw = self.raw.callbackArgValue(index);
        return convert.fromRuntimeValue(self.lua, raw, T) catch |err| return self.argConversionError(index, T, raw, err);
    }

    /// Returns null when absent or `nil`.
    pub fn optionalArg(self: *Context, index: usize, comptime T: type) !?T {
        if (index >= self.argCount()) return null;
        const raw = self.raw.callbackArgValue(index);
        if (raw == .nil) return null;
        return try self.arg(index, T);
    }

    pub fn pushReturn(self: *Context, value: anytype) !void {
        const raw_value = convert.toRuntimeValue(self.lua, value) catch |err| return self.returnConversionError(err);
        try self.raw.appendReturn(raw_value);
    }

    /// Replaces callback returns; tuples like `.{ a, b }` return multiple values.
    pub fn returnValues(self: *Context, values: anytype) !void {
        self.raw.clearReturns();
        try self.appendReturnValues(values);
    }

    /// Raises `value` as the Lua error object.
    pub fn raise(self: *Context, value: anytype) error{ LuaError, OutOfMemory, InvalidHandle } {
        const raw_value = convert.toRuntimeValue(self.lua, value) catch |err| return raiseConversionError(err);
        return self.raw.raise(raw_value);
    }

    /// Rooted handle to this callback's coroutine, usable beyond the callback.
    pub fn coroutine(self: *Context) !Coroutine {
        try coroutine_runtime.exposeThread(self.raw.thread);
        return convert.fromRuntimeValue(self.lua, .{ .thread = self.raw.thread }, Coroutine);
    }

    /// Reports whether this callback can yield across the current native boundary.
    pub fn isYieldable(self: *Context) bool {
        return coroutine_runtime.isYieldable(self.raw.thread);
    }

    /// Terminal yield: `return ctx.yield(.{values});`. Defers run before suspension; resume
    /// continues Lua with the resume arguments without reentering the Zig body.
    pub fn yield(self: *Context, values: anytype) error{ HostCallbackYield, LuaError, OutOfMemory, InvalidHandle } {
        if (coroutine_runtime.yieldRejection(self.raw.thread)) |message| return self.raise(message);
        self.returnValues(values) catch |err| return switch (err) {
            error.RuntimeError => self.raw.raise(self.raw.state.currentErrorValue()),
            else => raiseConversionError(err),
        };
        return error.HostCallbackYield;
    }

    /// Coroutine token valid only during this callback and until reset.
    pub fn coroutineIdentity(self: *Context) usize {
        return @intFromPtr(self.raw.thread);
    }

    /// Calls Lua on this coroutine within its budget; yielding is forbidden and errors propagate.
    pub fn callNonYielding(self: *Context, function: Function, args: anytype, comptime R: type) !R {
        try handle.validate(function.ref, self.lua);
        callbacks.bindDispatch(self.lua);
        const raw_args = try convert.convertArgs(self.lua, args);
        defer self.lua.allocator().free(raw_args);
        self.raw.thread.native_call_depth += 1;
        defer self.raw.thread.native_call_depth -= 1;
        const result = try call_mod.protectedCall(self.raw.state, self.raw.thread, try handle.rawValue(function.ref), raw_args);
        return switch (result) {
            .success => |values| blk: {
                defer self.lua.allocator().free(values);
                break :blk try convert.fromRuntimeResults(self.lua, values, R);
            },
            .failure => |value| self.raw.raise(value),
        };
    }

    fn argConversionError(self: *Context, index: usize, comptime T: type, raw: runtime.Value, err: anyerror) anyerror {
        return switch (err) {
            error.TypeMismatch => if (expectsInteger(T) and raw == .number)
                self.raw.failArgumentMessage(index, "number has no integer representation")
            else
                self.raw.failArgumentType(index, expectedTypeName(self.lua, T), raw),
            error.IntegerOutOfRange => self.raw.failArgumentMessage(index, "integer out of range"),
            error.UnsupportedType => self.raw.failArgumentMessage(index, "unsupported host argument type"),
            else => err,
        };
    }

    fn expectedTypeName(lua: *State, comptime T: type) []const u8 {
        if (comptime userdata_mod.PayloadOf(T)) |Payload| {
            if (userdata_mod.definedName(lua, Payload)) |name| return name;
        }
        return convert.expectedLuaType(T);
    }

    fn expectsInteger(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .int, .comptime_int => true,
            .optional => |optional| expectsInteger(optional.child),
            else => false,
        };
    }

    fn returnConversionError(self: *Context, err: anyerror) anyerror {
        return switch (err) {
            error.IntegerOutOfRange => self.raw.fail("host callback return integer out of range"),
            error.UnsupportedType => self.raw.fail("unsupported host callback return type"),
            else => err,
        };
    }

    fn raiseConversionError(err: anyerror) error{ LuaError, OutOfMemory, InvalidHandle } {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidHandle => error.InvalidHandle,
            else => error.LuaError,
        };
    }

    fn appendReturnValues(self: *Context, values: anytype) !void {
        const T = @TypeOf(values);
        const info = @typeInfo(T);
        if (info == .@"struct" and info.@"struct".is_tuple) {
            inline for (reflection.fieldNames(info.@"struct"), 0..) |_, index| try self.pushReturn(values[index]);
            return;
        }

        try self.pushReturn(values);
    }
};
