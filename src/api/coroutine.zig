const runtime = @import("../runtime.zig");
const runtime_types = @import("../runtime/types.zig");
const convert = @import("convert.zig");
const errors = @import("errors.zig");
const handle = @import("handle.zig");
const coroutine_mod = @import("../runtime/coroutine.zig");
const CallResult = errors.CallResult;
const Ref = handle.Ref;

pub const CoroutineStatus = runtime_types.ThreadStatus;

/// Converts only the active branch; strings are borrowed and handles released by `deinit`.
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

    /// Converts yields to `Y` and returns to `R`; Lua failures return `error.LuaError`.
    pub fn resumeCoroutine(self: Coroutine, args: anytype, comptime Y: type, comptime R: type) !ResumeResult(Y, R) {
        const result = try self.protectedResume(args, Y, R);
        return switch (result) {
            .ok => |value| value,
            .lua_error => |value| blk: {
                var failure = value;
                failure.deinit();
                break :blk error.LuaError;
            },
        };
    }

    /// Like `resumeCoroutine`, returning Lua errors as an `ErrorRef`.
    pub fn protectedResume(self: Coroutine, args: anytype, comptime Y: type, comptime R: type) !CallResult(ResumeResult(Y, R)) {
        const raw = try self.rawThread();
        const state = self.ref.state;
        const raw_args = try convert.convertArgs(state, args);
        defer state.allocator().free(raw_args);
        _ = errors.takeMemoryLimitExceeded(state);
        const result = coroutine_mod.resumeCoroutine(&state.raw_state, raw, raw_args) catch |err| {
            if (err == error.OutOfMemory and errors.takeMemoryLimitExceeded(state)) {
                return .{ .lua_error = try errors.memoryLimitErrorRef(state) };
            }
            return err;
        };
        return switch (result) {
            .success => |values| blk: {
                defer state.allocator().free(values);
                break :blk .{ .ok = if (raw.status == .suspended)
                    .{ .yielded = try convert.fromRuntimeResults(state, values, Y) }
                else
                    .{ .returned = try convert.fromRuntimeResults(state, values, R) } };
            },
            .failure => |value| blk: {
                if (errors.takeMemoryLimitExceeded(state)) break :blk .{ .lua_error = try errors.memoryLimitErrorRef(state) };
                try errors.setLastErrorValue(state, value);
                break :blk .{ .lua_error = try errors.refFromRuntime(state, value) };
            },
        };
    }

    pub fn status(self: Coroutine) !CoroutineStatus {
        return (try self.rawThread()).status;
    }

    /// State-local token valid while rooted and until reset.
    pub fn identity(self: Coroutine) !usize {
        return @intFromPtr(try self.rawThread());
    }

    /// Unwinds pending frames and `__close` handlers; rejects main, running, and normal coroutines.
    pub fn close(self: Coroutine) !void {
        const result = try self.protectedClose();
        switch (result) {
            .ok => {},
            .lua_error => |value| {
                var failure = value;
                failure.deinit();
                return error.LuaError;
            },
        }
    }

    /// Like `close`, returning Lua errors as an `ErrorRef` the caller must `deinit`.
    pub fn protectedClose(self: Coroutine) !CallResult(void) {
        const raw = try self.rawThread();
        const state = self.ref.state;
        const failure = coroutine_mod.closeCoroutineFromHost(&state.raw_state, raw, null) catch |err| switch (err) {
            error.RuntimeError, error.StackOverflow, error.UnsupportedOpcode => state.raw_state.currentErrorValue(),
            error.OutOfMemory => if (errors.takeMemoryLimitExceeded(state)) return .{ .lua_error = try errors.memoryLimitErrorRef(state) } else return err,
            else => return err,
        };
        if (failure) |value| {
            try errors.setLastErrorValue(state, value);
            return .{ .lua_error = try errors.refFromRuntime(state, value) };
        }
        return .{ .ok = {} };
    }

    fn rawThread(self: Coroutine) !*runtime.Thread {
        return switch (try handle.rawValue(self.ref)) {
            .thread => |raw| raw,
            else => error.TypeMismatch,
        };
    }
};
