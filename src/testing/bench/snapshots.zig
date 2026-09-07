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
const SnapshotWorkload = enum { bare_library, callbacks, modules, coroutines, no_op_small, no_op_large, sparse, dense, large_table, gc, resources, scoped_resources };

fn initializeSnapshotWorkload(allocator: std.mem.Allocator, workload: SnapshotWorkload) !zlua.State {
    var lua = try zlua.State.init(allocator, .{});
    errdefer lua.deinit();
    switch (workload) {
        .bare_library => {},
        .no_op_small => try lua.doString("data = {}; for i=1,16 do data[i] = {value=i} end", .{}),
        .no_op_large, .sparse, .dense, .gc => try lua.doString("data = {}; for i=1,10000 do data[i] = {value=i} end", .{}),
        .large_table => try lua.doString("data = {}; for i=1,100000 do data[i] = i end", .{}),
        .resources, .scoped_resources => {
            var resource = try lua.newUserdata(Resource, .{}, .{ .snapshot = .{ .copy = Resource.copy, .dispose = Resource.dispose, .tracking = if (workload == .scoped_resources) .scoped else .eager } });
            defer resource.deinit();
            try resource.method("increment", Resource.increment);
            try lua.setGlobal("resource", resource);
        },
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
    try lua.doString("function teardown() temporary = nil end", .{});
    try lua.doString(switch (workload) {
        .no_op_small, .no_op_large => "function work() end",
        .sparse => "function work() data[5000].value = 0 end",
        .dense => "function work() for i=1,#data do data[i].value = 0 end end",
        .large_table => "function work() data[50000] = 0 end",
        .gc => "function work() data = nil; collectgarbage('collect') end",
        .coroutines => "function work() assert(coroutine.resume(workers[1], 1)) end",
        .resources, .scoped_resources => "function work() resource:increment() end",
        else => "function work() temporary = {1,2,3} end",
    }, .{});
    return lua;
}

fn snapshotWork(lua: *zlua.State, name: []const u8) !void {
    var function = try lua.getGlobal(name, zlua.Function);
    defer function.deinit();
    try function.call(.{}, void);
}

const Resource = struct {
    value: usize = 0,
    fn copy(a: std.mem.Allocator, self: *const Resource) !*Resource {
        const result = try a.create(Resource);
        result.* = self.*;
        return result;
    }
    fn dispose(a: std.mem.Allocator, self: *Resource) void {
        a.destroy(self);
    }
    fn increment(self: *Resource) void {
        self.value += 1;
    }
};

const Sample = struct { capture: Metric, clone: Metric, mutation: Metric, reset_only: Metric, noop_reset: Metric, cycle: Metric, reset: Metric, rebuild: Metric };

fn measureClone(io: std.Io, checkpoint: *const zlua.Snapshot, counter: *CountingAllocator) !Metric {
    const before = counter.beginPhase();
    const start = Timestamp.now(io, .awake);
    var clone = try checkpoint.clone(counter.allocator());
    const elapsed = elapsedSince(io, start);
    defer clone.deinit();
    var metric = phaseMetric(counter, before, elapsed, clone.raw_state.allocationStats().bytes);
    metric.live_bytes = metric.live_bytes.? - before.live_bytes;
    metric.peak_bytes = metric.peak_bytes.? - before.live_bytes;
    return metric;
}

fn measureOperation(io: std.Io, lua: *zlua.State, checkpoint: *const zlua.Snapshot, counter: *CountingAllocator, comptime mutate: bool, comptime reset: bool) !Metric {
    const before = counter.beginPhase();
    const start = Timestamp.now(io, .awake);
    if (mutate) try snapshotWork(lua, "work");
    if (reset) try lua.reset(checkpoint);
    const elapsed = elapsedSince(io, start);
    return phaseMetric(counter, before, elapsed, lua.raw_state.allocationStats().bytes);
}

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
                .coroutines => "Resume one of 64 suspended Lua workers",
                .no_op_small => "No mutation with 16 baseline tables",
                .no_op_large => "No mutation with 10000 baseline tables",
                .sparse => "One write among 10000 baseline tables",
                .dense => "Write all 10000 baseline tables",
                .large_table => "One write to a 100000-entry array",
                .gc => "Drop and collect 10000 baseline tables",
                .resources => "Mutate one eager hooked host resource",
                .scoped_resources => "Mutate one scoped host resource",
            });
            continue;
        }
        collectCase(allocator, io, workload, iterations, warmup, suite) catch |err| {
            if (err == error.OutOfMemory) return err;
            inline for (comptime std.meta.fieldNames(Sample)) |operation| {
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
        sample.clone = try measureClone(io, &checkpoint, &vm_counter);
        // Restore first so every measured operation uses the same logical baseline.
        try lua.?.reset(&checkpoint);
        sample.noop_reset = try measureOperation(io, &lua.?, &checkpoint, &vm_counter, false, true);
        sample.mutation = try measureOperation(io, &lua.?, &checkpoint, &vm_counter, true, false);
        sample.reset_only = try measureOperation(io, &lua.?, &checkpoint, &vm_counter, false, true);
        sample.cycle = try measureOperation(io, &lua.?, &checkpoint, &vm_counter, true, true);
        sample.reset = try measureResetCycle(io, &lua.?, &checkpoint, &vm_counter);
        sample.rebuild = try measureRebuildCycle(io, &lua, workload, &vm_counter);
        if (index >= warmup) samples[index - warmup] = sample;
    }
    inline for (comptime std.meta.fieldNames(Sample)) |operation| {
        const metrics = try allocator.alloc(Metric, iterations);
        defer allocator.free(metrics);
        for (samples, metrics) |sample, *metric| metric.* = @field(sample, operation);
        try suite.add(.{
            .group = "snapshots",
            .case = name,
            .engine = "native",
            .build_mode = @tagName(@import("builtin").mode),
            .operation = operation,
            .scope = operationScope(operation),
            .memory_scope = if (std.mem.eql(u8, operation, "capture")) .checkpoint else if (std.mem.eql(u8, operation, "clone")) .new_state else .vm,
            .iterations = iterations,
            .warmup = warmup,
            .samples = metrics,
        });
    }
}

fn operationScope(comptime operation: []const u8) []const u8 {
    if (std.mem.eql(u8, operation, "capture")) return "Capture only; destruction excluded";
    if (std.mem.eql(u8, operation, "clone")) return "Clone only; destruction excluded";
    if (std.mem.eql(u8, operation, "mutation")) return "Work only, including first writes and call overhead";
    if (std.mem.eql(u8, operation, "reset_only")) return "Reset only, after work";
    if (std.mem.eql(u8, operation, "noop_reset")) return "Reset only, without intervening work";
    if (std.mem.eql(u8, operation, "cycle")) return "Work and reset";
    if (std.mem.eql(u8, operation, "reset")) return "Teardown and reset";
    return "Teardown, deinit, and equivalent initialization";
}
