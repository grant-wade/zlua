const runtime = @import("../runtime.zig");
const runtime_types = @import("../runtime/types.zig");
const convert = @import("convert.zig");
const errors = @import("errors.zig");
const handle = @import("handle.zig");
const coroutine_mod = @import("../runtime/coroutine.zig");
const debug_mod = @import("../runtime/debug.zig");
const CallBudget = @import("function.zig").CallBudget;
const Ref = handle.Ref;
const ResumeOptions = @import("options.zig").ResumeOptions;

pub const CoroutineStatus = runtime_types.ThreadStatus;

/// Converts only the active branch; handles are released by `deinit`.
/// Conversion failure does not rewind execution.
pub fn ResumeResult(comptime Y: type, comptime R: type) type {
    return union(enum) {
        yielded: Y,
        returned: R,

        pub fn deinit(self: *@This()) void {
            switch (self.*) {
                .yielded => |*value| convert.deinitIfOwned(Y, value),
                .returned => |*value| convert.deinitIfOwned(R, value),
            }
            self.* = undefined;
        }
    };
}

/// Rooted coroutine handle; copies are not owners. Reset invalidates it; deinit before its state.
pub const Coroutine = struct {
    ref: Ref,

    /// Releases only the root; use `close` to unwind pending frames.
    pub fn deinit(self: *Coroutine) void {
        self.ref.deinit();
        self.* = undefined;
    }

    /// Converts yields to `Y` and returns to `R`; Lua failures return `error.LuaError`, and
    /// `State.takeError` returns the error value.
    pub fn resumeCoroutine(self: Coroutine, args: anytype, comptime Y: type, comptime R: type) !ResumeResult(Y, R) {
        return self.resumeCoroutineWith(args, Y, R, .{});
    }

    pub fn resumeCoroutineWith(self: Coroutine, args: anytype, comptime Y: type, comptime R: type, options: ResumeOptions) !ResumeResult(Y, R) {
        const raw = try self.rawThread();
        const state = self.ref.state;
        const raw_args = try convert.convertArgs(state, args);
        _ = errors.takeMemoryLimitExceeded(state);
        const resumable = raw.status == .suspended;
        const budget = CallBudget.begin(state, options.max_instructions);
        defer budget.end(state);
        const result = coroutine_mod.resumeCoroutine(&state.raw_state, raw, &raw_args) catch |err| {
            if (err == error.OutOfMemory and errors.takeMemoryLimitExceeded(state)) return errors.memoryLimitError(state);
            return err;
        };
        switch (result) {
            .success => |values| {
                defer state.allocator().free(values);
                if (raw.status == .suspended) return .{ .yielded = try convert.fromRuntimeResults(state, values, Y) };
                return .{ .returned = try convert.fromRuntimeResults(state, values, R) };
            },
            .failure => |value| {
                if (errors.takeMemoryLimitExceeded(state)) return errors.memoryLimitError(state);
                try errors.setLastErrorValue(state, value);
                if (options.traceback and resumable) state.last_error_traceback = try debug_mod.formatTraceback(&state.raw_state, raw, false);
                return error.LuaError;
            },
        }
    }

    pub fn status(self: Coroutine) !CoroutineStatus {
        return (try self.rawThread()).status;
    }

    /// State-local token valid while rooted and until reset.
    pub fn identity(self: Coroutine) !usize {
        return @intFromPtr(try self.rawThread());
    }

    /// Unwinds pending frames and `__close` handlers; rejects main, running, and normal coroutines.
    /// A Lua error raised while closing returns `error.LuaError`.
    pub fn close(self: Coroutine) !void {
        const raw = try self.rawThread();
        const state = self.ref.state;
        const failure = coroutine_mod.closeCoroutineFromHost(&state.raw_state, raw, null) catch |err| switch (err) {
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => state.raw_state.currentErrorValue(),
            error.OutOfMemory => if (errors.takeMemoryLimitExceeded(state)) return errors.memoryLimitError(state) else return err,
            else => return err,
        };
        if (failure) |value| {
            try errors.setLastErrorValue(state, value);
            return error.LuaError;
        }
    }

    fn rawThread(self: Coroutine) !*runtime.Thread {
        return switch (try handle.rawValue(self.ref)) {
            .thread => |raw| raw,
            else => error.TypeMismatch,
        };
    }
};
