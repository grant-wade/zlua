const std = @import("std");
const runtime = @import("../runtime.zig");
const callbacks = @import("callbacks.zig");
const convert = @import("convert.zig");
const errors = @import("errors.zig");
const handle = @import("handle.zig");
const BytecodeDumpOptions = @import("options.zig").BytecodeDumpOptions;
const CallOptions = @import("options.zig").CallOptions;
const Ref = handle.Ref;
const State = @import("state.zig").State;
const entry_mod = @import("../runtime/entry.zig");

/// Rooted handle to any Lua function: a closure, host callback, or standard library function.
pub const Function = struct {
    ref: Ref,

    pub fn deinit(self: *Function) void {
        self.ref.deinit();
        self.* = undefined;
    }

    /// Converts the first result to `R`, or every result to a tuple `R`; Lua failures return
    /// `error.LuaError`, and `State.takeError` returns the error value.
    pub fn call(self: Function, args: anytype, comptime R: type) !R {
        return self.callWith(args, R, .{});
    }

    pub fn callWith(self: Function, args: anytype, comptime R: type, options: CallOptions) !R {
        const state = self.ref.state;
        try handle.validate(self.ref, state);
        callbacks.bindDispatch(state);
        const raw_args = try convert.convertArgs(state, args);
        errors.clearLastError(state);

        var traceback: ?[]u8 = null;
        defer if (traceback) |text| state.allocator().free(text);
        const handler = try hostErrorHandler(state, options, &traceback);
        const budget = CallBudget.begin(state, options.max_instructions);
        defer budget.end(state);
        var result_buffer: [result_buffer_len]runtime.Value = undefined;
        const results = entry_mod.callFunctionInto(&state.raw_state, try handle.rawValue(self.ref), &raw_args, handler, &result_buffer) catch |err| {
            const captured = errors.captureLuaError(state, err);
            if (captured == error.LuaError) {
                state.last_error_traceback = traceback;
                traceback = null;
            }
            return captured;
        };
        defer if (results.ptr != &result_buffer) state.allocator().free(results);
        return convert.fromRuntimeResults(state, results, R);
    }

    /// Writes the function as a binary chunk; native callbacks return `error.TypeMismatch`.
    pub fn dumpBytecode(self: Function, writer: *std.Io.Writer, options: BytecodeDumpOptions) !void {
        const allocator = self.ref.state.allocator();
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        try runtime.dumpClosureBinary(allocator, &out, try self.rawClosure(), options.strip_debug);
        try writer.writeAll(out.items);
    }

    fn rawClosure(self: Function) !*runtime.Closure {
        return switch (try handle.rawValue(self.ref)) {
            .closure => |closure| closure,
            else => error.TypeMismatch,
        };
    }
};

/// Results a call returns without allocating.
const result_buffer_len = 8;

pub const CallBudget = struct {
    active: bool,
    previous: ?u64,

    pub fn begin(state: *State, max_instructions: ?u64) CallBudget {
        const max = max_instructions orelse return .{ .active = false, .previous = null };
        return .{ .active = true, .previous = state.raw_state.budget.beginCall(max) };
    }

    pub fn end(self: CallBudget, state: *State) void {
        if (self.active) state.raw_state.budget.endCall(self.previous);
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
