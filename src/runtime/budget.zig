const std = @import("std");
const failure_mod = @import("failure.zig");
const State = @import("state.zig").State;
const types = @import("types.zig");

const Thread = types.Thread;

/// Instructions between interrupt polls; the fast loop also polls at backward jumps and calls.
const interrupt_poll_interval: u64 = 1024;

/// Interrupt request shared with host threads. Heap-allocated so its address
/// survives moves of the owning state.
pub const InterruptControl = struct {
    requested: std.atomic.Value(bool) = .init(false),

    pub fn request(self: *InterruptControl) void {
        self.requested.store(true, .release);
    }

    pub fn clear(self: *InterruptControl) void {
        self.requested.store(false, .release);
    }

    pub fn isRequested(self: *const InterruptControl) bool {
        return self.requested.load(.acquire);
    }
};

/// Instruction counting, `max_instructions` and per-call budgets, and host interrupts.
pub const Budget = struct {
    instructions: u64 = 0,
    /// `instructions` at the last budget reset.
    base: u64 = 0,
    /// Deadline of the innermost budgeted host call, narrowed by enclosing ones.
    call_deadline: ?u64 = null,
    /// `instructions` at which `checkpointReached` runs; zero forces a recompute.
    checkpoint: u64 = 0,
    /// Allocated on first use.
    interrupt: ?*InterruptControl = null,

    fn parentState(budget: *Budget) *State {
        return @alignCast(@fieldParentPtr("budget", budget));
    }

    fn constParentState(budget: *const Budget) *const State {
        return @alignCast(@fieldParentPtr("budget", budget));
    }

    /// Per-instruction safepoint; the hot path is one comparison against `checkpoint`.
    pub inline fn checkLimits(budget: *Budget, thread: *Thread) !void {
        if (budget.instructions >= budget.checkpoint) try budget.checkpointReached(thread);
        budget.instructions = budget.instructions +| 1;
    }

    /// Interrupts and exhausted budgets leave the checkpoint in place so every later
    /// safepoint raises again; Lua code cannot catch them and keep running.
    noinline fn checkpointReached(budget: *Budget, thread: *Thread) !void {
        if (budget.interruptRequested()) return error.Interrupted;
        if (budget.exhausted()) {
            const state = budget.parentState();
            const err = failure_mod.failRuntimeDetail(state, thread, "instruction limit exceeded");
            state.error_handled = true;
            return err;
        }
        budget.checkpoint = budget.nextCheckpoint();
    }

    /// Polled periodically by long-running native functions.
    pub fn checkInterrupt(budget: *Budget) !void {
        if (budget.interruptRequested()) {
            budget.checkpoint = 0;
            return error.Interrupted;
        }
    }

    fn exhausted(budget: *const Budget) bool {
        if (budget.constParentState().options.max_instructions) |max| {
            if (budget.instructions -| budget.base >= max) return true;
        }
        if (budget.call_deadline) |deadline| {
            if (budget.instructions >= deadline) return true;
        }
        return false;
    }

    fn nextCheckpoint(budget: *const Budget) u64 {
        var next: u64 = std.math.maxInt(u64);
        if (budget.constParentState().options.max_instructions) |max| next = @min(next, budget.base +| max);
        if (budget.call_deadline) |deadline| next = @min(next, deadline);
        if (budget.interrupt != null) next = @min(next, budget.instructions +| interrupt_poll_interval);
        return next;
    }

    pub fn interruptControl(budget: *Budget) !*InterruptControl {
        if (budget.interrupt) |control| return control;
        const control = try budget.parentState().allocator.create(InterruptControl);
        control.* = .{};
        budget.interrupt = control;
        budget.checkpoint = 0;
        return control;
    }

    pub inline fn interruptRequested(budget: *const Budget) bool {
        const control = budget.interrupt orelse return false;
        return control.requested.load(.monotonic);
    }

    pub fn clearInterrupt(budget: *Budget) void {
        if (budget.interrupt) |control| control.clear();
        budget.checkpoint = 0;
    }

    pub inline fn fastLoopInterrupted(budget: *Budget) bool {
        if (!budget.interruptRequested()) return false;
        budget.checkpoint = 0;
        return true;
    }

    /// The uncounted fast loop is disabled while any instruction budget applies.
    pub inline fn active(budget: *const Budget) bool {
        return budget.constParentState().options.max_instructions != null or budget.call_deadline != null;
    }

    pub fn used(budget: *const Budget) u64 {
        return budget.instructions -| budget.base;
    }

    /// Restarts the cumulative `max_instructions` budget.
    pub fn reset(budget: *Budget) void {
        budget.base = budget.instructions;
        budget.checkpoint = 0;
    }

    /// Limits a host call, including nested calls and coroutines, to `max` further
    /// instructions. Returns the enclosing deadline for `endCall`.
    pub fn beginCall(budget: *Budget, max: u64) ?u64 {
        const previous = budget.call_deadline;
        const deadline = budget.instructions +| max;
        budget.call_deadline = if (previous) |outer| @min(outer, deadline) else deadline;
        budget.checkpoint = 0;
        return previous;
    }

    /// Restores the deadline returned by `beginCall`.
    pub fn endCall(budget: *Budget, previous: ?u64) void {
        budget.call_deadline = previous;
        budget.checkpoint = 0;
    }

    pub fn consumeInterrupt(budget: *Budget) void {
        if (budget.interrupt) |control| control.clear();
        budget.checkpoint = 0;
    }
};
