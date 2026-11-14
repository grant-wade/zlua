const std = @import("std");
const reflection = @import("../reflection.zig");
const runtime = @import("../runtime.zig");
const coroutine_runtime = @import("../runtime/coroutine.zig");
const debug_runtime = @import("../runtime/debug.zig");
const callbacks = @import("callbacks.zig");
const convert = @import("convert.zig");
const decode_mod = @import("decode.zig");
const handle = @import("handle.zig");
const table_mod = @import("table.zig");
const Coroutine = @import("coroutine.zig").Coroutine;
const Function = @import("function.zig").Function;
const State = @import("state.zig").State;
const userdata_mod = @import("userdata.zig");
const Value = @import("value.zig").Value;
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

/// A Lua function on a callback's coroutine.
pub const Caller = struct {
    /// Chunk name as given to `load`, such as `@path` or `=name`; borrows VM memory.
    source: []const u8,
    /// Null when the function's debug info is stripped.
    line: ?usize,

    /// Buffer length for `shortSource`.
    pub const short_source_len = debug_runtime.chunk_id_size;

    /// The chunk name as error messages show it, written to `buffer`.
    pub fn shortSource(self: Caller, buffer: *[short_source_len]u8) []const u8 {
        return debug_runtime.chunkId(buffer, self.source);
    }
};

/// Callback context for functions created with `State.newFunction`.
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

    /// The Lua function `level` calls up this callback's coroutine, not counting native functions;
    /// level 0 is the innermost one.
    pub fn caller(self: *Context, level: usize) ?Caller {
        const frames = self.raw.thread.frames.items;
        var remaining = level;
        var index = frames.len;
        while (index > 0) {
            index -= 1;
            const frame = frames[index];
            const source = frame.closure.proto.source_name;
            if (debug_runtime.isCoroutineEntryFrame(frame) or std.mem.eql(u8, source, "=[C]")) continue;
            if (remaining == 0) return .{
                .source = source,
                .line = if (frame.closure.stripped_debug) null else debug_runtime.lineForFrame(frame),
            };
            remaining -= 1;
        }
        return null;
    }

    /// Line of the Lua function running on this callback's coroutine, or null when there is
    /// none or its debug info is stripped.
    pub fn currentLine(self: *Context) ?usize {
        const frames = self.raw.thread.frames.items;
        if (frames.len == 0) return null;
        const frame = frames[frames.len - 1];
        if (frame.closure.stripped_debug) return null;
        return debug_runtime.lineForFrame(frame);
    }

    pub fn argCount(self: *Context) usize {
        return self.raw.argCount();
    }

    /// A `[]const u8` argument borrows VM memory until the callback returns.
    pub fn arg(self: *Context, index: usize, comptime T: type) !T {
        const raw = self.raw.callbackArgValue(index);
        return convert.fromRuntimeBorrowed(self.lua, raw, T) catch |err| return self.argConversionError(index, T, raw, err);
    }

    /// Decodes an argument by type like `decode`, allocating strings and slices with `allocator`;
    /// a value that doesn't fit raises a `bad argument` error.
    pub fn decodeArg(self: *Context, index: usize, comptime T: type, allocator: std.mem.Allocator) !T {
        var value = try convert.fromRuntimeValue(self.lua, self.raw.callbackArgValue(index), Value);
        defer value.deinit();
        var diagnostic: decode_mod.Diagnostic = .{ .gpa = self.lua.allocator() };
        defer diagnostic.deinit();
        return decode_mod.decode(T, value, .{ .allocator = allocator, .diagnostic = &diagnostic }) catch |err| switch (err) {
            error.Invalid => self.raw.failArgumentMessage(index, diagnostic.text),
            error.OutOfMemory => error.OutOfMemory,
        };
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

    /// Raises the formatted message as the Lua error object, after the position of the innermost
    /// Lua function when it has debug info.
    pub fn raisef(self: *Context, comptime fmt: []const u8, args: anytype) error{ LuaError, OutOfMemory, InvalidHandle } {
        const allocator = self.lua.allocator();
        const message = if (self.caller(0)) |at| blk: {
            const line = at.line orelse break :blk try std.fmt.allocPrint(allocator, fmt, args);
            var buffer: [debug_runtime.chunk_id_size]u8 = undefined;
            break :blk try std.fmt.allocPrint(allocator, "{s}:{d}: " ++ fmt, .{ at.shortSource(&buffer), line } ++ args);
        } else try std.fmt.allocPrint(allocator, fmt, args);
        defer allocator.free(message);
        return self.raise(message);
    }

    /// Raises `bad argument #index + 1 to 'name' (message)`; the first argument has index 0.
    pub fn argError(self: *Context, index: usize, message: []const u8) runtime.RuntimeError {
        return self.raw.failArgumentMessage(index, message);
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

    /// Ends the callback by calling `function`, which may yield, then typed callback `continuation`
    /// with its results and `saved` bound; the continuation's returns are this callback's.
    pub fn callThen(self: *Context, function: Function, args: anytype, comptime continuation: anytype, saved: anytype) error{ HostCallbackTailCall, LuaError, OutOfMemory, InvalidHandle } {
        const target = convert.toRuntimeValue(self.lua, function) catch |err| return raiseConversionError(err);
        const raw_args = convert.convertArgs(self.lua, args) catch |err| return raiseConversionError(err);
        return self.finishWith(target, &raw_args, continuation, saved);
    }

    /// Ends the callback by yielding `values`, then calls `continuation` with the resume arguments
    /// as `callThen` does.
    pub fn yieldThen(self: *Context, values: anytype, comptime continuation: anytype, saved: anytype) error{ HostCallbackTailCall, LuaError, OutOfMemory, InvalidHandle } {
        if (coroutine_runtime.yieldRejection(self.raw.thread)) |message| return self.raise(message);
        const raw_values = convert.convertArgs(self.lua, values) catch |err| return raiseConversionError(err);
        return self.finishWith(.native_coroutine_yield, &raw_values, continuation, saved);
    }

    fn finishWith(self: *Context, target: runtime.Value, args: []const runtime.Value, comptime continuation: anytype, saved: anytype) error{ HostCallbackTailCall, LuaError, OutOfMemory, InvalidHandle } {
        self.prepareTailCall(target, args, callbacks.typedHostFn(continuation), saved) catch |err| return switch (err) {
            error.RuntimeError => self.raw.raise(self.raw.state.currentErrorValue()),
            else => raiseConversionError(err),
        };
        return error.HostCallbackTailCall;
    }

    fn prepareTailCall(self: *Context, target: runtime.Value, args: []const runtime.Value, continuation: callbacks.HostFn, saved: anytype) !void {
        const helper = try callbacks.continuationHelper(self.lua);
        const raw_saved = try convert.convertArgs(self.lua, saved);
        var next = try callbacks.createClosure(self.lua, self.functionName(), continuation, &raw_saved);
        defer next.deinit();
        self.raw.clearReturns();
        try self.raw.appendReturn(try convert.toRuntimeValue(self.lua, next));
        try self.raw.appendReturn(target);
        for (args) |value| try self.raw.appendReturn(value);
        self.raw.tail_callee = helper;
    }

    /// The number of values bound to this callback by `State.newClosure`.
    pub fn upvalueCount(self: *Context) usize {
        const closure = self.raw.closure orelse return 0;
        return callbacks.closureValueCount(closure);
    }

    /// The value bound at `index`, or nil past the last one. A `[]const u8` or `*T` borrows VM
    /// memory until the callback returns or replaces the value.
    pub fn upvalue(self: *Context, index: usize, comptime T: type) !T {
        return convert.fromRuntimeBorrowed(self.lua, self.rawUpvalue(index), T);
    }

    /// Replaces the value bound at `index`, which must be less than `upvalueCount()`.
    pub fn setUpvalue(self: *Context, index: usize, value: anytype) !void {
        if (index >= self.upvalueCount()) return self.raw.fail("upvalue index out of range");
        const raw_value = convert.toRuntimeValue(self.lua, value) catch |err| return self.returnConversionError(err);
        try table_mod.storeRaw(self.lua, self.raw.closure.?, .{ .integer = @intCast(index + callbacks.closure_values_start) }, raw_value);
    }

    fn rawUpvalue(self: *Context, index: usize) runtime.Value {
        if (index >= self.upvalueCount()) return .nil;
        return self.raw.closure.?.get(.{ .integer = @intCast(index + callbacks.closure_values_start) });
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
        self.raw.thread.native_call_depth += 1;
        defer self.raw.thread.native_call_depth -= 1;
        const result = try call_mod.protectedCall(self.raw.state, self.raw.thread, try handle.rawValue(function.ref), &raw_args);
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
            error.UserdataClosed => self.raw.failArgumentMessage(index, "userdata is closed"),
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
