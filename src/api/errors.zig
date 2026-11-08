const std = @import("std");
const runtime = @import("../runtime.zig");
const handle = @import("handle.zig");
const Ref = handle.Ref;
const State = @import("state.zig").State;
const Value = @import("value.zig").Value;

/// `LuaError`: Lua syntax/runtime error. `LuaExit`: `os.exit` ran; see `State.exitRequest`.
/// `Interrupted`: stopped by an `InterruptHandle`. Lua cannot catch exits or interrupts.
pub const Error = error{ LuaError, LuaExit, Interrupted };
pub const UnsupportedOption = error{UnsupportedOption};
pub const ConversionError = error{
    TypeMismatch,
    IntegerOutOfRange,
    UnsupportedType,
    ArityMismatch,
};

const memory_limit_error_message = "memory limit exceeded";

/// Rooted handle to a Lua error value.
pub const ErrorRef = struct {
    ref: Ref,
    /// Owned traceback; read it with `traceback`.
    traceback_text: ?[]const u8 = null,

    pub fn deinit(self: *ErrorRef) void {
        if (self.traceback_text) |text| self.ref.state.allocator().free(text);
        self.ref.deinit();
        self.* = undefined;
    }

    /// Traceback when `CallOptions.traceback` or `ResumeOptions.traceback` was set, formatted
    /// like `debug.traceback`; valid until `deinit`.
    pub fn traceback(self: ErrorRef) ?[]const u8 {
        return self.traceback_text;
    }

    pub fn value(self: ErrorRef) !Value {
        return self.ref.value();
    }

    /// Writes the error value as the CLI reports it.
    pub fn writeMessage(self: ErrorRef, writer: *std.Io.Writer) !void {
        try writeErrorValue(self.ref.state, try handle.rawValue(self.ref), writer);
    }
};

pub fn refFromRuntime(state: *State, raw: runtime.Value) !ErrorRef {
    return .{ .ref = try handle.fromRuntime(state, raw) };
}

pub fn captureLuaError(state: *State, err: anyerror) anyerror {
    switch (err) {
        error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => {
            setLastErrorValue(state, state.raw_state.currentErrorValue()) catch |root_err| return root_err;
            return error.LuaError;
        },
        error.OutOfMemory => if (takeMemoryLimitExceeded(state)) {
            state.raw_state.last_error = .{ .diagnostic = memory_limit_error_message };
            setLastErrorValue(state, state.raw_state.currentErrorValue()) catch {};
            return error.LuaError;
        } else return err,
        else => return err,
    }
}

pub fn takeMemoryLimitExceeded(state: *State) bool {
    const allocator_ptr = state.memory_limit_allocator orelse return false;
    if (!allocator_ptr.exceeded) return false;
    allocator_ptr.exceeded = false;
    return true;
}

/// Records the memory limit failure as the last Lua error and returns `error.LuaError`.
pub fn memoryLimitError(state: *State) error{LuaError} {
    state.raw_state.last_error = .{ .diagnostic = memory_limit_error_message };
    setLastErrorValue(state, state.raw_state.currentErrorValue()) catch {};
    return error.LuaError;
}

pub fn writeErrorValue(state: *State, value: runtime.Value, writer: *std.Io.Writer) !void {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator());
    try runtime.appendErrorValue(state.allocator(), &out, value);
    try writer.writeAll(out.items);
}

pub fn setLastErrorValue(state: *State, value: runtime.Value) !void {
    clearLastErrorTraceback(state);
    if (state.last_error_root) |index| state.raw_state.unrootValue(index);
    state.last_error_root = null;
    state.last_error_root = try state.raw_state.rootValue(value);
}

pub fn lastErrorValue(state: *State) runtime.Value {
    if (state.last_error_root) |index| return state.raw_state.rootedValue(index);
    return state.raw_state.currentErrorValue();
}

pub fn clearLastErrorTraceback(state: *State) void {
    if (state.last_error_traceback) |text| state.allocator().free(text);
    state.last_error_traceback = null;
}
