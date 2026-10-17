const std = @import("std");
const types = @import("types.zig");

const Thread = types.Thread;

/// Instructions between interrupt polls; the fast loop also polls at backward jumps and calls.
pub const interrupt_poll_interval: u64 = 1024;

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

/// Per-instruction safepoint; the hot path is one comparison against `instruction_checkpoint`.
pub inline fn checkExecutionLimits(comptime State: type, self: *State, thread: *Thread) !void {
    if (self.instruction_count >= self.instruction_checkpoint) try executionCheckpoint(State, self, thread);
    self.instruction_count = self.instruction_count +| 1;
}

/// Interrupts and exhausted budgets leave the checkpoint in place so every later
/// safepoint raises again; Lua code cannot catch them and keep running.
pub noinline fn executionCheckpoint(comptime State: type, self: *State, thread: *Thread) !void {
    if (self.interruptRequested()) return error.Interrupted;
    if (instructionBudgetExhausted(State, self)) {
        const err = self.failRuntimeDetail(thread, "instruction limit exceeded");
        self.error_handled = true;
        return err;
    }
    self.instruction_checkpoint = nextCheckpoint(State, self);
}

/// Polled periodically by long-running native functions.
pub fn checkInterrupt(comptime State: type, self: *State) !void {
    if (self.interruptRequested()) {
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
