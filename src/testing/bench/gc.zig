//! GC work distributions. Setup is outside each measured step. The counting
//! allocator reports physical VM storage, including retained rollback copies;
//! runtime_bytes reports the live managed heap used by collector pacing.
const std = @import("std");
const zlua = @import("../../root.zig");
const results = @import("results.zig");
const Options = @import("options.zig").Options;
const allocation = @import("allocation.zig");
const Timestamp = std.Io.Timestamp;
const Workload = enum { transient, stable_small, stable_large, old_container, weak_tables, finalizers, incremental };

pub fn collect(allocator: std.mem.Allocator, io: std.Io, options: Options, suite: *results.Suite) !void {
    const iterations = options.iterations orelse 1000;
    const warmup = options.warmup orelse 100;
    for (std.enums.values(Workload)) |workload| {
        const name = @tagName(workload);
        if (!options.matches("gc", "native", name)) continue;
        if (options.list) {
            try suite.addCase("gc", "native", name, "Basic collector steps; setup excluded, physical and managed memory recorded");
            continue;
        }
        var counter = allocation.CountingAllocator{ .backing = allocator };
        var lua = try zlua.State.init(counter.allocator(), .{ .gc = .{ .running = false } });
        defer lua.deinit();
        try lua.doString(
            \\data = {}; weak = setmetatable({}, {__mode='kv'})
            \\finalized = 0; mt = {__gc=function() finalized=finalized+1 end}
            \\function tick() collectgarbage('step', 0) end
        , .{});
        const count: usize = switch (workload) {
            .stable_large, .old_container, .incremental => 10000,
            else => 32,
        };
        const data = lua.raw_state.getGlobal("data");
        for (0..count) |i| try lua.raw_state.setTableValue(data, .{ .integer = @intCast(i + 1) }, try lua.raw_state.newTableWithHints(0, 1));
        if (workload == .incremental) _ = lua.setGcMode(.incremental);
        var snapshot = try lua.snapshot(allocator);
        defer snapshot.deinit();
        const samples = try allocator.alloc(results.Metric, iterations);
        defer allocator.free(samples);
        for (0..warmup + iterations) |i| {
            if (workload != .incremental) {
                try lua.reset();
                try prepare(&lua, workload);
            }
            // Acquiring the host handle is setup; finalizer timing includes the
            // Lua call that supplies an execution thread to collectgarbage.
            var tick = try lua.getGlobal("tick", zlua.Function);
            defer tick.deinit();
            const before = counter.beginPhase();
            const start = Timestamp.now(io, .awake);
            if (workload == .finalizers) try tick.call(.{}, void) else _ = try lua.stepGc(.{});
            const elapsed = allocation.elapsedSince(io, start);
            if (i >= warmup) samples[i - warmup] = allocation.phaseMetric(&counter, before, elapsed, lua.raw_state.currentAllocationTotal());
        }
        try suite.add(.{
            .group = "gc",
            .case = name,
            .engine = "native",
            .operation = "step",
            .build_mode = @tagName(@import("builtin").mode),
            .scope = if (workload == .finalizers) "Basic step plus Lua host-call overhead" else "One basic collector step",
            .memory_scope = .vm,
            .iterations = iterations,
            .warmup = warmup,
            .samples = samples,
        });
    }
}

fn prepare(lua: *zlua.State, workload: Workload) !void {
    switch (workload) {
        .transient => for (0..256) |_| {
            _ = try lua.raw_state.newTableWithHints(4, 0);
        },
        .stable_small, .stable_large => for (0..8) |_| {
            _ = try lua.raw_state.newTableWithHints(0, 0);
        },
        .old_container => {
            const leaf = lua.raw_state.getGlobal("data").table.get(.{ .integer = 5000 });
            try lua.raw_state.setTableValue(leaf, .{ .string = "new" }, try lua.raw_state.newTableWithHints(0, 0));
        },
        .weak_tables => {
            const weak = lua.raw_state.getGlobal("weak");
            for (0..64) |_| {
                const key = try lua.raw_state.newTableWithHints(0, 0);
                const value = try lua.raw_state.newTableWithHints(0, 0);
                try lua.raw_state.setTableValue(weak, key, value);
            }
        },
        .finalizers => try lua.doString("for i=1,32 do setmetatable({}, mt) end", .{}),
        .incremental => unreachable,
    }
}
