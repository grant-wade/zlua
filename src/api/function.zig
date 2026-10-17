const std = @import("std");
const runtime = @import("../runtime.zig");
const callbacks = @import("callbacks.zig");
const convert = @import("convert.zig");
const errors = @import("errors.zig");
const handle = @import("handle.zig");
const BytecodeDumpOptions = @import("options.zig").BytecodeDumpOptions;
const CallOptions = @import("options.zig").CallOptions;
const CallResult = errors.CallResult;
const Ref = handle.Ref;
const State = @import("state.zig").State;

/// Rooted handle to a Lua function or loaded chunk.
pub const Function = struct {
    ref: Ref,

    pub fn deinit(self: *Function) void {
        self.ref.deinit();
        self.* = undefined;
    }

    /// Converts the first result, or a `Tuple`, to `R`; Lua failures return `error.LuaError`.
    /// `[]const u8` results borrow VM memory; see `Value.string`.
    pub fn call(self: Function, args: anytype, comptime R: type) !R {
        return self.callWith(args, R, .{});
    }

    /// `call` with `CallOptions`; on `error.LuaError` the handled error value and traceback
    /// are kept on the state.
    pub fn callWith(self: Function, args: anytype, comptime R: type, options: CallOptions) !R {
        const state = self.ref.state;
        try handle.validate(self.ref, state);
        callbacks.bindDispatch(state);
        const raw_args = try convert.convertArgs(state, args);
        defer state.allocator().free(raw_args);

        var traceback: ?[]u8 = null;
        defer if (traceback) |text| state.allocator().free(text);
        const handler = try hostErrorHandler(state, options, &traceback);
        const budget = CallBudget.begin(state, options);
        defer budget.end(state);
        const results = state.raw_state.callFunctionHandled(try handle.rawValue(self.ref), raw_args, handler) catch |err| {
            const captured = errors.captureLuaError(state, err);
            if (captured == error.LuaError) {
                state.last_error_traceback = traceback;
                traceback = null;
            }
            return captured;
        };
        defer state.allocator().free(results);
        return convert.fromRuntimeResults(state, results, R);
    }

    /// Like `call`, but returns Lua failures as `CallResult.lua_error`.
    pub fn protectedCall(self: Function, args: anytype, comptime R: type) !CallResult(R) {
        return self.protectedCallWith(args, R, .{});
    }

    /// `protectedCall` with `CallOptions`; a captured traceback is owned by the `ErrorRef`.
    pub fn protectedCallWith(self: Function, args: anytype, comptime R: type, options: CallOptions) !CallResult(R) {
        const state = self.ref.state;
        try handle.validate(self.ref, state);
        callbacks.bindDispatch(state);
        const raw_args = try convert.convertArgs(state, args);
        defer state.allocator().free(raw_args);

        var traceback: ?[]u8 = null;
        defer if (traceback) |text| state.allocator().free(text);
        const handler = try hostErrorHandler(state, options, &traceback);
        const budget = CallBudget.begin(state, options);
        defer budget.end(state);
        const result = state.raw_state.protectedCallFunctionHandled(try handle.rawValue(self.ref), raw_args, handler) catch |err| {
            if (err == error.OutOfMemory and errors.takeMemoryLimitExceeded(state)) {
                return .{ .lua_error = try errors.memoryLimitErrorRef(state) };
            }
            return err;
        };
        switch (result) {
            .success => |values| {
                defer state.allocator().free(values);
                return .{ .ok = try convert.fromRuntimeResults(state, values, R) };
            },
            .failure => |value| {
                try errors.setLastErrorValue(state, value);
                var error_ref = try errors.refFromRuntime(state, value);
                error_ref.traceback_text = traceback;
                traceback = null;
                return .{ .lua_error = error_ref };
            },
        }
    }

    /// Native callbacks return `error.TypeMismatch`.
    /// The caller frees the result with the state's allocator.
    pub fn dumpBytecode(self: Function, options: BytecodeDumpOptions) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.ref.state.allocator());
        try runtime.dumpClosureBinary(self.ref.state.allocator(), &out, try self.rawClosure(), options.strip_debug);
        return out.toOwnedSlice(self.ref.state.allocator());
    }

    fn rawClosure(self: Function) !*runtime.Closure {
        return switch (try handle.rawValue(self.ref)) {
            .closure => |closure| closure,
            else => error.TypeMismatch,
        };
    }
};

const CallBudget = struct {
    active: bool,
    previous: ?u64,

    fn begin(state: *State, options: CallOptions) CallBudget {
        const max = options.max_instructions orelse return .{ .active = false, .previous = null };
        return .{ .active = true, .previous = state.raw_state.beginCallInstructionBudget(max) };
    }

    fn end(self: CallBudget, state: *State) void {
        if (self.active) state.raw_state.endCallInstructionBudget(self.previous);
    }
};

fn hostErrorHandler(state: *State, options: CallOptions, traceback: *?[]u8) !runtime.HostErrorHandler {
    return .{
        .traceback = if (options.traceback) traceback else null,
        .message_handler = if (options.message_handler) |handler| blk: {
            try handle.validate(handler.ref, state);
            break :blk state.raw_state.rootedValue(handler.ref.index);
        } else .nil,
    };
}
