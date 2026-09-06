const std = @import("std");
const zlua = @import("../../root.zig");
const results = @import("results.zig");
const Options = @import("options.zig").Options;
const allocation = @import("allocation.zig");
const CountingAllocator = allocation.CountingAllocator;
const CounterSnapshot = allocation.CounterSnapshot;
const phaseMetric = allocation.phaseMetric;
const elapsedSince = allocation.elapsedSince;
const Metric = results.Metric;
const Timestamp = std.Io.Timestamp;
const trivial_chunk = "";
const host_chunk = "return host_tag(host_add(host_double(20), 2))";
const SnapshotWorkload = enum { bare_library, callbacks, modules, coroutines };

fn initializeSnapshotWorkload(allocator: std.mem.Allocator, workload: SnapshotWorkload) !zlua.State {
    var lua = try zlua.State.init(allocator, .{});
    errdefer lua.deinit();
    switch (workload) {
        .bare_library => {},
        .callbacks => {
            for (0..128) |i| {
                var buffer: [32]u8 = undefined;
                const name = try std.fmt.bufPrint(&buffer, "host_{d}", .{i});
                var callback = try lua.registerTyped(name, struct {
                    fn identity(v: i64) i64 {
                        return v;
                    }
                }.identity);
                try lua.setGlobal(name, callback);
                callback.deinit();
            }
            try lua.doString("config = {}; for i=1,128 do config[i] = _G['host_' .. (i-1)](i) end", .{});
        },
        .modules => {
            try lua.openLibs(.{ .custom = .{ .package = true } });
            for (0..16) |i| {
                var path_buffer: [32]u8 = undefined;
                const path = try std.fmt.bufPrint(&path_buffer, "module{d}.lua", .{i});
                try lua.addMemoryFile(path,
                    \\local M = {values = {}}
                    \\for i=1,64 do M.values[i] = {name='item'..i, value=i*i} end
                    \\local count = 0
                    \\function M.next() count = count + 1; return count end
                    \\return M
                );
            }
            try lua.doString("modules = {}; for i=0,15 do modules[i+1] = require('module'..i) end", .{});
        },
        .coroutines => try lua.doString(
            \\workers = {}
            \\for i=1,64 do
            \\ workers[i] = coroutine.create(function(...)
            \\  local config = {...}; local sum = 0
            \\  for j=1,128 do sum = sum + j end
            \\  while true do sum = sum + coroutine.yield(sum, config) end
            \\ end)
            \\ assert(coroutine.resume(workers[i], i, 'worker'))
            \\end
        , .{}),
    }
    try lua.doString("function teardown() temporary = nil end; function work() temporary = {1,2,3} end", .{});
    return lua;
}

fn snapshotWork(lua: *zlua.State, name: []const u8) !void {
    var function = try lua.getGlobal(name, zlua.Function);
    defer function.deinit();
    try function.call(.{}, void);
}

const Sample = struct { capture: Metric, reset: Metric, rebuild: Metric };

fn measureCapture(io: std.Io, lua: *zlua.State, counter: *CountingAllocator) !Metric {
    const before = counter.beginPhase();
    const start = Timestamp.now(io, .awake);
    var captured = try lua.snapshot(counter.allocator());
    const elapsed = elapsedSince(io, start);
    defer captured.deinit();
    var metric = phaseMetric(counter, before, elapsed, 0);
    // Only this capture's storage; exclude the reusable checkpoint already alive.
    metric.live_bytes = metric.live_bytes.? - before.live_bytes;
    metric.peak_bytes = metric.peak_bytes.? - before.live_bytes;
    metric.runtime_bytes = null;
    return metric;
}

fn measureResetCycle(io: std.Io, lua: *zlua.State, checkpoint: *const zlua.Snapshot, counter: *CountingAllocator) !Metric {
    try snapshotWork(lua, "work");
    const before = counter.beginPhase();
    const start = Timestamp.now(io, .awake);
    try snapshotWork(lua, "teardown");
    try lua.reset(checkpoint);
    const elapsed = elapsedSince(io, start);
    // VM peak includes the live state and its replacement; checkpoint storage is separate.
    return phaseMetric(counter, before, elapsed, lua.raw_state.allocationStats().bytes);
}

fn measureRebuildCycle(io: std.Io, lua: *?zlua.State, workload: SnapshotWorkload, counter: *CountingAllocator) !Metric {
    try snapshotWork(&lua.*.?, "work");
    const before = counter.beginPhase();
    const start = Timestamp.now(io, .awake);
    try snapshotWork(&lua.*.?, "teardown");
    lua.*.?.deinit();
    lua.* = null;
    lua.* = try initializeSnapshotWorkload(counter.allocator(), workload);
    const elapsed = elapsedSince(io, start);
    return phaseMetric(counter, before, elapsed, lua.*.?.raw_state.allocationStats().bytes);
}

fn measureBareInit(io: std.Io) !Metric {
    var counter: CountingAllocator = .{ .backing = std.heap.smp_allocator };
    const before = counter.beginPhase();
    const start = Timestamp.now(io, .awake);
    var lua = try zlua.State.init(counter.allocator(), .{});
    const elapsed = elapsedSince(io, start);
    defer lua.deinit();
    return phaseMetric(&counter, before, elapsed, lua.raw_state.allocationStats().bytes);
}

pub fn collect(allocator: std.mem.Allocator, io: std.Io, options: Options, suite: *results.Suite) !void {
    const iterations = options.iterations orelse 1000;
    const warmup = options.warmup orelse 100;
    for (std.enums.values(SnapshotWorkload)) |workload| {
        const name = @tagName(workload);
        if (!options.matches("snapshots", "native", name)) continue;
        if (options.list) {
            try suite.addCase("snapshots", "native", name, switch (workload) {
                .bare_library => "Default libraries and teardown/work functions",
                .callbacks => "128 host callbacks and configuration values",
                .modules => "16 loaded modules with tables and mutable closures",
                .coroutines => "64 suspended Lua workers",
            });
            continue;
        }
        collectCase(allocator, io, workload, iterations, warmup, suite) catch |err| {
            if (err == error.OutOfMemory) return err;
            inline for (.{ "capture", "reset", "rebuild" }) |operation| {
                try suite.add(.{
                    .group = "snapshots",
                    .case = name,
                    .engine = "native",
                    .build_mode = @tagName(@import("builtin").mode),
                    .operation = operation,
                    .scope = "Snapshot cycle",
                    .iterations = iterations,
                    .warmup = warmup,
                    .status = .failed,
                    .reason = @errorName(err),
                });
            }
        };
    }
    if (options.matches("snapshots", "native", "bare-api-init")) {
        if (options.list) {
            try suite.addCase("snapshots", "native", "bare-api-init", "Independent API initialization baseline");
            return;
        }
        for (0..warmup) |_| _ = try measureBareInit(io);
        const samples = try allocator.alloc(Metric, iterations);
        defer allocator.free(samples);
        for (samples) |*sample| sample.* = try measureBareInit(io);
        try suite.add(.{
            .group = "snapshots",
            .case = "bare-api-init",
            .engine = "native",
            .build_mode = @tagName(@import("builtin").mode),
            .operation = "init",
            .scope = "API initialization only; destruction excluded",
            .memory_scope = .new_state,
            .iterations = iterations,
            .warmup = warmup,
            .samples = samples,
        });
    }
}

fn collectCase(allocator: std.mem.Allocator, io: std.Io, workload: SnapshotWorkload, iterations: usize, warmup: usize, suite: *results.Suite) !void {
    const name = @tagName(workload);
    var vm_counter: CountingAllocator = .{ .backing = std.heap.smp_allocator };
    var checkpoint_counter: CountingAllocator = .{ .backing = std.heap.smp_allocator };
    var lua: ?zlua.State = try initializeSnapshotWorkload(vm_counter.allocator(), workload);
    defer if (lua) |*state| state.deinit();
    var checkpoint = try lua.?.snapshot(checkpoint_counter.allocator());
    defer checkpoint.deinit();
    const samples = try allocator.alloc(Sample, iterations);
    defer allocator.free(samples);
    for (0..try std.math.add(usize, iterations, warmup)) |index| {
        var sample: Sample = undefined;
        sample.capture = try measureCapture(io, &lua.?, &checkpoint_counter);
        sample.reset = try measureResetCycle(io, &lua.?, &checkpoint, &vm_counter);
        sample.rebuild = try measureRebuildCycle(io, &lua, workload, &vm_counter);
        if (index >= warmup) samples[index - warmup] = sample;
    }
    inline for (.{ "capture", "reset", "rebuild" }) |operation| {
        const metrics = try allocator.alloc(Metric, iterations);
        defer allocator.free(metrics);
        for (samples, metrics) |sample, *metric| metric.* = @field(sample, operation);
        try suite.add(.{
            .group = "snapshots",
            .case = name,
            .engine = "native",
            .build_mode = @tagName(@import("builtin").mode),
            .operation = operation,
            .scope = if (std.mem.eql(u8, operation, "capture")) "Capture only; destruction excluded" else if (std.mem.eql(u8, operation, "reset")) "Teardown and reset" else "Teardown, deinit, and equivalent initialization",
            .memory_scope = if (std.mem.eql(u8, operation, "capture")) .checkpoint else .vm,
            .iterations = iterations,
            .warmup = warmup,
            .samples = metrics,
        });
    }
}
