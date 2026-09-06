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
const Selection = struct {
    name: []const u8,
    stdlib: zlua.runtime.StdlibMode,
    host_functions: bool = false,
};

const selections = [_]Selection{
    .{ .name = "none", .stdlib = .none },
    .{ .name = "base", .stdlib = .base },
    .{ .name = "safe", .stdlib = .safe },
    .{ .name = "full", .stdlib = .full },
    .{ .name = "base+host-3", .stdlib = .base, .host_functions = true },
};

const Phase = enum {
    state,
    globals,
    libraries,
    gc_baseline,
    register,
    startup_total,
    load,
    call,
    deinit,
    first_chunk,
};

const phase_names = [_][]const u8{
    "state",
    "globals",
    "libraries",
    "gc-baseline",
    "register-3",
    "startup-total",
    "load",
    "call",
    "deinit",
    "first-chunk",
};

const Sample = struct {
    phases: [phase_names.len]Metric,
};

const InitObserver = struct {
    io: std.Io,
    counter: *CountingAllocator,
    sample: *Sample,
    phase_start: Timestamp,
    phase_before: CounterSnapshot,

    fn observe(self: *InitObserver, phase: zlua.runtime.StartupPhase, state: *zlua.runtime.State) void {
        const elapsed = elapsedSince(self.io, self.phase_start);
        self.sample.phases[@intFromEnum(phase)] = phaseMetric(self.counter, self.phase_before, elapsed, state.allocationStats().bytes);
        self.phase_before = self.counter.beginPhase();
        self.phase_start = Timestamp.now(self.io, .awake);
    }
};

fn runSample(io: std.Io, selection: Selection) !Sample {
    var counter: CountingAllocator = .{ .backing = std.heap.smp_allocator };
    const allocator = counter.allocator();
    var sample: Sample = .{ .phases = @splat(.{}) };

    var init_observer: InitObserver = .{
        .io = io,
        .counter = &counter,
        .sample = &sample,
        .phase_start = Timestamp.now(io, .awake),
        .phase_before = counter.beginPhase(),
    };
    // Wrap the observed runtime so host registration uses the embedding API
    // without losing the individual initialization timings.
    var api_state: zlua.State = .{
        .base_allocator = allocator,
        .raw_state = try zlua.runtime.State.initWithOptionsObserved(allocator, .{ .stdlib = selection.stdlib }, &init_observer, InitObserver.observe),
    };
    var alive = true;
    defer if (alive) api_state.deinit();
    const state = &api_state.raw_state;

    if (selection.host_functions) {
        const before = counter.beginPhase();
        const start = Timestamp.now(io, .awake);
        try registerHostFunctions(&api_state);
        sample.phases[@intFromEnum(Phase.register)] = phaseMetric(&counter, before, elapsedSince(io, start), state.allocationStats().bytes);
    }

    const startup_index = @intFromEnum(Phase.startup_total);
    var startup_elapsed: u64 = 0;
    for (0..startup_index) |phase_index| startup_elapsed += sample.phases[phase_index].elapsed_ns;
    const startup_snapshot = counter.snapshot();
    sample.phases[startup_index] = .{
        .elapsed_ns = startup_elapsed,
        .allocations = startup_snapshot.allocations,
        .resizes = startup_snapshot.resizes,
        .requested_bytes = startup_snapshot.requested_bytes,
        .live_bytes = startup_snapshot.live_bytes,
        .peak_bytes = counter.peak_bytes,
        .runtime_bytes = state.allocationStats().bytes,
    };

    const load_before = counter.beginPhase();
    const load_start = Timestamp.now(io, .awake);
    const source = if (selection.host_functions) host_chunk else trivial_chunk;
    const loaded = try state.loadSourceAsClosure(source);
    const load_elapsed = elapsedSince(io, load_start);
    sample.phases[@intFromEnum(Phase.load)] = phaseMetric(&counter, load_before, load_elapsed, state.allocationStats().bytes);

    const call_before = counter.beginPhase();
    const call_start = Timestamp.now(io, .awake);
    const returned = try state.callLoadedClosure(loaded.closure, &.{});
    const call_elapsed = elapsedSince(io, call_start);
    const valid = if (selection.host_functions)
        returned.len == 2 and returned[0] == .integer and returned[0].integer == 42 and
            returned[1] == .string and std.mem.eql(u8, returned[1].string, "host-ok")
    else
        returned.len == 0;
    allocator.free(returned);
    if (!valid) return error.BenchmarkUnexpectedResult;
    sample.phases[@intFromEnum(Phase.call)] = phaseMetric(&counter, call_before, call_elapsed, state.allocationStats().bytes);

    const before_deinit = counter.snapshot();
    const first_chunk_index = @intFromEnum(Phase.first_chunk);
    const first_chunk_elapsed = startup_elapsed + load_elapsed + call_elapsed;
    sample.phases[first_chunk_index] = .{
        .elapsed_ns = first_chunk_elapsed,
        .allocations = before_deinit.allocations,
        .resizes = before_deinit.resizes,
        .requested_bytes = before_deinit.requested_bytes,
        .live_bytes = before_deinit.live_bytes,
        .peak_bytes = counter.peak_bytes,
        .runtime_bytes = state.allocationStats().bytes,
    };

    const deinit_before = counter.beginPhase();
    const deinit_start = Timestamp.now(io, .awake);
    api_state.deinit();
    alive = false;
    const deinit_elapsed = elapsedSince(io, deinit_start);
    sample.phases[@intFromEnum(Phase.deinit)] = phaseMetric(&counter, deinit_before, deinit_elapsed, 0);
    if (counter.live_bytes != 0) return error.BenchmarkAllocatorLeak;
    return sample;
}

fn hostAdd(lhs: i64, rhs: i64) i64 {
    return lhs + rhs;
}

fn hostDouble(value: i64) i64 {
    return value * 2;
}

fn hostTag(ctx: *zlua.Context) !void {
    try ctx.returnValues(.{ try ctx.arg(0, i64), "host-ok" });
}

fn registerHostFunctions(state: *zlua.State) !void {
    var add = try state.registerTyped("host_add", hostAdd);
    defer add.deinit();
    try state.setGlobal("host_add", add);
    var double = try state.registerTyped("host_double", hostDouble);
    defer double.deinit();
    try state.setGlobal("host_double", double);
    var tag = try state.register("host_tag", hostTag);
    defer tag.deinit();
    try state.setGlobal("host_tag", tag);
}

pub fn collect(allocator: std.mem.Allocator, io: std.Io, options: Options, suite: *results.Suite) !void {
    const iterations = options.iterations orelse 1000;
    const warmup = options.warmup orelse 100;
    for (selections) |selection| {
        if (!options.matches("startup", "native", selection.name)) continue;
        if (options.list) {
            try suite.addCase("startup", "native", selection.name, "State creation, libraries, and first chunk");
            continue;
        }
        collectCase(allocator, io, selection, iterations, warmup, suite) catch |err| {
            if (err == error.OutOfMemory) return err;
            try suite.add(.{
                .group = "startup",
                .case = selection.name,
                .engine = "native",
                .build_mode = @tagName(@import("builtin").mode),
                .operation = "startup-total",
                .scope = "In-process startup",
                .iterations = iterations,
                .warmup = warmup,
                .status = .failed,
                .reason = @errorName(err),
            });
        };
    }
}

fn collectCase(allocator: std.mem.Allocator, io: std.Io, selection: Selection, iterations: usize, warmup: usize, suite: *results.Suite) !void {
    const samples = try allocator.alloc(Sample, iterations);
    defer allocator.free(samples);
    for (0..warmup) |_| _ = try runSample(io, selection);
    for (samples) |*sample| sample.* = try runSample(io, selection);
    for (phase_names, 0..) |name, phase| {
        if (phase == @intFromEnum(Phase.register) and !selection.host_functions) continue;
        const metrics = try allocator.alloc(Metric, iterations);
        defer allocator.free(metrics);
        for (samples, metrics) |sample, *metric| metric.* = sample.phases[phase];
        try suite.add(.{
            .group = "startup",
            .case = selection.name,
            .engine = "native",
            .build_mode = @tagName(@import("builtin").mode),
            .operation = name,
            .scope = "In-process phase; totals sum initialization/load/call phases",
            .memory_scope = .vm,
            .iterations = iterations,
            .warmup = warmup,
            .samples = metrics,
        });
    }
}
