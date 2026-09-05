const std = @import("std");
const zlua = @import("zlua");

const Timestamp = std.Io.Timestamp;

const default_iterations: usize = 1000;
const default_warmup: usize = 100;
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

const Metric = struct {
    elapsed_ns: u64 = 0,
    allocations: u64 = 0,
    resizes: u64 = 0,
    requested_bytes: u64 = 0,
    live_bytes: u64 = 0,
    peak_bytes: u64 = 0,
    runtime_bytes: u64 = 0,
};

const Sample = struct {
    phases: [phase_names.len]Metric,
};

const CounterSnapshot = struct {
    allocations: u64,
    resizes: u64,
    requested_bytes: u64,
    live_bytes: u64,
};

const CountingAllocator = struct {
    backing: std.mem.Allocator,
    allocations: u64 = 0,
    resizes: u64 = 0,
    requested_bytes: u64 = 0,
    live_bytes: u64 = 0,
    peak_bytes: u64 = 0,
    phase_peak_bytes: u64 = 0,

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn beginPhase(self: *CountingAllocator) CounterSnapshot {
        self.phase_peak_bytes = self.live_bytes;
        return self.snapshot();
    }

    fn snapshot(self: *const CountingAllocator) CounterSnapshot {
        return .{
            .allocations = self.allocations,
            .resizes = self.resizes,
            .requested_bytes = self.requested_bytes,
            .live_bytes = self.live_bytes,
        };
    }

    fn accountSize(self: *CountingAllocator, old_len: usize, new_len: usize) void {
        if (new_len >= old_len) {
            const growth = new_len - old_len;
            self.live_bytes += growth;
            self.requested_bytes += growth;
        } else {
            self.live_bytes -= old_len - new_len;
        }
        self.peak_bytes = @max(self.peak_bytes, self.live_bytes);
        self.phase_peak_bytes = @max(self.phase_peak_bytes, self.live_bytes);
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const result = self.backing.rawAlloc(len, alignment, return_address) orelse return null;
        self.allocations += 1;
        self.accountSize(0, len);
        return result;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        if (!self.backing.rawResize(memory, alignment, new_len, return_address)) return false;
        self.resizes += 1;
        self.accountSize(memory.len, new_len);
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const result = self.backing.rawRemap(memory, alignment, new_len, return_address) orelse return null;
        self.resizes += 1;
        self.accountSize(memory.len, new_len);
        return result;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        self.backing.rawFree(memory, alignment, return_address);
        self.live_bytes -= memory.len;
    }
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

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var iterations = default_iterations;
    var warmup = default_warmup;
    try parseArgs(args[1..], &iterations, &warmup);

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const out = &stdout_writer.interface;

    try out.print("native startup (ReleaseFast), iterations={d}, warmup={d}\n", .{ iterations, warmup });
    try out.print("selection     phase           median-ns      p95-ns  alloc  resize  requested-B    live-B    peak-B runtime-B\n", .{});

    for (selections) |selection| {
        const samples = try init.gpa.alloc(Sample, iterations);
        defer init.gpa.free(samples);

        for (0..warmup) |_| _ = try runSample(init.io, selection);
        for (samples) |*sample| sample.* = try runSample(init.io, selection);
        for (phase_names, 0..) |phase_name, phase_index| {
            if (phase_index == @intFromEnum(Phase.register) and !selection.host_functions) continue;
            try printPhase(init.gpa, out, selection.name, phase_name, samples, phase_index);
        }
        try out.writeByte('\n');
    }
    try out.flush();
}

fn parseArgs(args: []const []const u8, iterations: *usize, warmup: *usize) !void {
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--iterations")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            iterations.* = try positiveUsize(args[index]);
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            iterations.* = try positiveUsize(arg[13..]);
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            warmup.* = try std.fmt.parseInt(usize, args[index], 10);
        } else if (std.mem.startsWith(u8, arg, "--warmup=")) {
            warmup.* = try std.fmt.parseInt(usize, arg[9..], 10);
        } else {
            return error.UnknownOption;
        }
    }
}

fn positiveUsize(value: []const u8) !usize {
    const parsed = try std.fmt.parseInt(usize, value, 10);
    if (parsed == 0) return error.InvalidOptionValue;
    return parsed;
}

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
    const results = try state.callLoadedClosure(loaded.closure, &.{});
    const call_elapsed = elapsedSince(io, call_start);
    const valid = if (selection.host_functions)
        results.len == 2 and results[0] == .integer and results[0].integer == 42 and
            results[1] == .string and std.mem.eql(u8, results[1].string, "host-ok")
    else
        results.len == 0;
    allocator.free(results);
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

fn elapsedSince(io: std.Io, start: Timestamp) u64 {
    return @intCast(start.durationTo(Timestamp.now(io, .awake)).toNanoseconds());
}

fn phaseMetric(counter: *const CountingAllocator, before: CounterSnapshot, elapsed_ns: u64, runtime_bytes: usize) Metric {
    const after = counter.snapshot();
    return .{
        .elapsed_ns = elapsed_ns,
        .allocations = after.allocations - before.allocations,
        .resizes = after.resizes - before.resizes,
        .requested_bytes = after.requested_bytes - before.requested_bytes,
        .live_bytes = after.live_bytes,
        .peak_bytes = counter.phase_peak_bytes,
        .runtime_bytes = runtime_bytes,
    };
}

const Field = enum {
    elapsed_ns,
    allocations,
    resizes,
    requested_bytes,
    live_bytes,
    peak_bytes,
    runtime_bytes,
};

fn printPhase(allocator: std.mem.Allocator, out: *std.Io.Writer, selection: []const u8, phase_name: []const u8, samples: []const Sample, phase_index: usize) !void {
    const median_ns = try percentile(allocator, samples, phase_index, .elapsed_ns, 50);
    const p95_ns = try percentile(allocator, samples, phase_index, .elapsed_ns, 95);
    const allocations = try percentile(allocator, samples, phase_index, .allocations, 50);
    const resizes = try percentile(allocator, samples, phase_index, .resizes, 50);
    const requested = try percentile(allocator, samples, phase_index, .requested_bytes, 50);
    const live = try percentile(allocator, samples, phase_index, .live_bytes, 50);
    const peak = try percentile(allocator, samples, phase_index, .peak_bytes, 50);
    const runtime_bytes = try percentile(allocator, samples, phase_index, .runtime_bytes, 50);
    try out.print("{s:<13} {s:<13} {d:>11} {d:>11} {d:>6} {d:>7} {d:>12} {d:>9} {d:>9} {d:>9}\n", .{
        selection, phase_name, median_ns, p95_ns, allocations, resizes, requested, live, peak, runtime_bytes,
    });
}

fn percentile(allocator: std.mem.Allocator, samples: []const Sample, phase_index: usize, field: Field, percent: usize) !u64 {
    const values = try allocator.alloc(u64, samples.len);
    defer allocator.free(values);
    for (samples, 0..) |sample, index| values[index] = metricField(sample.phases[phase_index], field);
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    const rank = @max(@divFloor(percent * values.len + 99, 100), 1) - 1;
    return values[rank];
}

fn metricField(metric: Metric, field: Field) u64 {
    return switch (field) {
        .elapsed_ns => metric.elapsed_ns,
        .allocations => metric.allocations,
        .resizes => metric.resizes,
        .requested_bytes => metric.requested_bytes,
        .live_bytes => metric.live_bytes,
        .peak_bytes => metric.peak_bytes,
        .runtime_bytes => metric.runtime_bytes,
    };
}
