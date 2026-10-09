//! A watchdog thread interrupts a runaway script, which `pcall` cannot catch.
//! Per-call instruction budgets and tracebacks bound and diagnose other calls.
const std = @import("std");
const zlua = @import("zlua");

const script =
    \\ticks = 0
    \\function runaway()
    \\  -- A sandboxed script cannot protect itself from the watchdog.
    \\  while true do
    \\    pcall(function() ticks = ticks + 1 end)
    \\  end
    \\end
    \\local function check(level)
    \\  if level > 3 then error("level too high") end
    \\end
    \\function validate(level) check(level) end
;

const Watchdog = struct {
    io: std.Io,
    handle: zlua.InterruptHandle,
    done: std.atomic.Value(bool) = .init(false),

    /// Interrupts the script after `timeout_ms` unless the host finished first.
    fn run(self: *Watchdog, timeout_ms: u32) void {
        var waited: u32 = 0;
        while (waited < timeout_ms) : (waited += 5) {
            if (self.done.load(.acquire)) return;
            self.io.sleep(std.Io.Duration.fromMilliseconds(5), .awake) catch return;
        }
        self.handle.interrupt();
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();
    try lua.doString(script, .{ .name = "=plugin.lua" });

    var runaway = try lua.getGlobal("runaway", zlua.Function);
    defer runaway.deinit();

    // Start the watchdog, then run the script on this thread.
    var watchdog = Watchdog{ .io = init.io, .handle = try lua.interruptHandle() };
    const thread = try std.Thread.spawn(.{}, Watchdog.run, .{ &watchdog, 50 });
    const result = runaway.call(.{}, void);
    watchdog.done.store(true, .release);
    thread.join();

    if (result) |_| return error.ExpectedInterrupt else |err| switch (err) {
        error.Interrupted => {},
        else => return err,
    }
    const ticks = try lua.getGlobal("ticks", i64);
    std.debug.print("watchdog stopped runaway() after {d} ticks\n", .{ticks});

    // The state remains usable after an interrupt.
    var validate = try lua.getGlobal("validate", zlua.Function);
    defer validate.deinit();
    try validate.call(.{1}, void);

    // A per-call budget stops the same script deterministically.
    if (runaway.callWith(.{}, void, .{ .max_instructions = 100_000 })) |_| return error.ExpectedLimit else |err| switch (err) {
        error.LuaError => {
            const message = try lua.errorMessage();
            defer lua.allocator().free(message);
            std.debug.print("budgeted call failed: {s}\n", .{message});
        },
        else => return err,
    }

    // A traceback captured at the error point shows where validation failed.
    const checked = try validate.protectedCallWith(.{5}, void, .{ .traceback = true });
    switch (checked) {
        .ok => return error.ExpectedLuaError,
        .lua_error => |error_ref| {
            var failure = error_ref;
            defer failure.deinit();
            const message = try failure.message();
            defer lua.allocator().free(message);
            std.debug.print("{s}\n{s}\n", .{ message, failure.traceback().? });
        },
    }
}
