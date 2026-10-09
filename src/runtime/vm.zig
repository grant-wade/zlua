const std = @import("std");
const types = @import("types.zig");

const Thread = types.Thread;

/// Main-loop instructions between interrupt polls once a state has an
/// interrupt control. The fast loop also polls at backward jumps and calls.
pub const interrupt_poll_interval: u64 = 1024;

/// Interrupt request shared between a state and host threads.
///
/// The state allocates it on first request and frees it in `deinit`, so its
/// address stays stable when the owning state value moves. Only `requested`
/// is touched from other threads.
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

/// Per-instruction safepoint for the general dispatch loop. The common case
/// is one comparison against `instruction_checkpoint`; budgets, interrupt
/// polls, and recomputation after a budget change share the cold path.
pub inline fn checkExecutionLimits(comptime State: type, self: *State, thread: *Thread) !void {
    if (self.instruction_count >= self.instruction_checkpoint) try executionCheckpoint(State, self, thread);
    self.instruction_count = self.instruction_count +| 1;
}

/// Checkpoint slow path. Interrupts and exhausted budgets leave the
/// checkpoint in place, so every later safepoint raises again until the host
/// clears the interrupt or the budget scope ends: Lua code cannot catch them
/// and keep running.
pub noinline fn executionCheckpoint(comptime State: type, self: *State, thread: *Thread) !void {
    if (self.interruptRequested()) return error.Interrupted;
    if (instructionBudgetExhausted(State, self)) return self.failRuntimeDetail(thread, "instruction limit exceeded");
    self.instruction_checkpoint = nextCheckpoint(State, self);
}

/// Raises `error.Interrupted` when a host thread has requested an interrupt.
/// Long-running native functions call this periodically.
pub fn checkInterrupt(comptime State: type, self: *State) !void {
    if (self.interruptRequested()) {
        // Make the next VM safepoint take the slow path as well.
        self.instruction_checkpoint = 0;
        return error.Interrupted;
    }
}

pub fn instructionBudgetExhausted(comptime State: type, self: *const State) bool {
    if (self.options.max_instructions) |max| {
        if (self.instruction_count -| self.instruction_budget_base >= max) return true;
    }
    if (self.call_instruction_deadline) |deadline| {
        if (self.instruction_count >= deadline) return true;
    }
    return false;
}

fn nextCheckpoint(comptime State: type, self: *const State) u64 {
    var next: u64 = std.math.maxInt(u64);
    if (self.options.max_instructions) |max| next = @min(next, self.instruction_budget_base +| max);
    if (self.call_instruction_deadline) |deadline| next = @min(next, deadline);
    if (self.interrupt != null) next = @min(next, self.instruction_count +| interrupt_poll_interval);
    return next;
}
