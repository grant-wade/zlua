const std = @import("std");
const api = @import("../api.zig");
const fixtures = @import("fixtures.zig");
const generators = @import("generators.zig");
const parallel = @import("parallel.zig");
const process = @import("process.zig");

const Dir = std.Io.Dir;
const File = std.Io.File;

const Outcome = enum { ok, @"error", interrupted, any };

/// Harness-owned limits a fixture may override in its leading `-- key: value` comments.
pub const Metadata = struct {
    outcome: Outcome = .ok,
    /// Substring required in the error message.
    message: []const u8 = "",
    stdlib: enum { safe, full } = .safe,
    max_memory: ?usize = 64 << 20,
    max_instructions: ?u64 = 1_000_000,
    call_instructions: ?u64 = null,
    max_output: usize = 16 << 20,
    interrupt_ms: ?u32 = null,
    /// Longest allowed gap between an interrupt request and the call returning.
    latency_ms: ?u32 = null,
    binary_chunks: bool = false,
    /// Fixtures that need more stack than this to reach the limit they test skip smaller stacks.
    min_stack: usize = 0,
    /// Also runs the fixture failing each allocation in turn and under collector stress.
    fault_sweep: bool = false,
};

pub fn parseMetadata(source: []const u8) !Metadata {
    var result: Metadata = .{};
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, "--")) break;
        const comment = std.mem.trim(u8, line[2..], " \t");
        const colon = std.mem.indexOfScalar(u8, comment, ':') orelse return error.InvalidMetadata;
        const key = std.mem.trim(u8, comment[0..colon], " \t");
        const value = std.mem.trim(u8, comment[colon + 1 ..], " \t");
        if (std.mem.eql(u8, key, "outcome")) {
            result.outcome = std.meta.stringToEnum(Outcome, value) orelse return error.InvalidMetadata;
        } else if (std.mem.eql(u8, key, "message")) {
            result.message = value;
        } else if (std.mem.eql(u8, key, "stdlib")) {
            result.stdlib = std.meta.stringToEnum(@TypeOf(result.stdlib), value) orelse return error.InvalidMetadata;
        } else if (std.mem.eql(u8, key, "max-memory")) {
            result.max_memory = try optionalInt(usize, value);
        } else if (std.mem.eql(u8, key, "max-instructions")) {
            result.max_instructions = try optionalInt(u64, value);
        } else if (std.mem.eql(u8, key, "call-instructions")) {
            result.call_instructions = try std.fmt.parseInt(u64, value, 10);
        } else if (std.mem.eql(u8, key, "max-output")) {
            result.max_output = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "interrupt-ms")) {
            result.interrupt_ms = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, key, "latency-ms")) {
            result.latency_ms = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, key, "min-stack")) {
            result.min_stack = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "fault-sweep")) {
            result.fault_sweep = std.mem.eql(u8, value, "true");
        } else if (std.mem.eql(u8, key, "binary-chunks")) {
            result.binary_chunks = std.mem.eql(u8, value, "true");
        } else {
            return error.InvalidMetadata;
        }
    }
    return result;
}

fn optionalInt(comptime T: type, value: []const u8) !?T {
    if (std.mem.eql(u8, value, "none")) return null;
    return try std.fmt.parseInt(T, value, 10);
}

const TrackingAllocator = struct {
    child: std.mem.Allocator,
    live: usize = 0,
    peak: usize = 0,

    fn allocator(self: *TrackingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn grew(self: *TrackingAllocator, old_len: usize, new_len: usize) void {
        self.live = self.live - old_len + new_len;
        self.peak = @max(self.peak, self.live);
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(context));
        const memory = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.grew(0, len);
        return memory;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *TrackingAllocator = @ptrCast(@alignCast(context));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.grew(memory.len, new_len);
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(context));
        const result = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.grew(memory.len, new_len);
        return result;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *TrackingAllocator = @ptrCast(@alignCast(context));
        self.child.rawFree(memory, alignment, ret_addr);
        self.live -= memory.len;
    }
};

/// Room left on a fixture's thread for frames below the last stack check.
const native_stack_margin = 128 << 10;

/// Fails allocation number `fail_at`, and every later one when `sticky`.
const FaultAllocator = struct {
    child: std.mem.Allocator,
    count: usize = 0,
    fail_at: usize = std.math.maxInt(usize),
    sticky: bool = false,
    armed: bool = true,

    fn allocator(self: *FaultAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn fails(self: *FaultAllocator) bool {
        if (!self.armed) return false;
        const index = self.count;
        self.count += 1;
        return index == self.fail_at or (self.sticky and index > self.fail_at);
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *FaultAllocator = @ptrCast(@alignCast(context));
        if (self.fails()) return null;
        return self.child.rawAlloc(len, alignment, ret_addr);
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *FaultAllocator = @ptrCast(@alignCast(context));
        if (new_len > memory.len and self.fails()) return false;
        return self.child.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *FaultAllocator = @ptrCast(@alignCast(context));
        if (new_len > memory.len and self.fails()) return null;
        return self.child.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *FaultAllocator = @ptrCast(@alignCast(context));
        self.child.rawFree(memory, alignment, ret_addr);
    }
};

const object_count = 2;
var gc_calls: [object_count]u32 = @splat(0);
var finalizer_calls: [object_count]u32 = @splat(0);

/// Host resource exposed to fixtures as the globals `res` and `res2`.
const Resource = struct {
    id: usize,

    pub fn value(self: *Resource) i64 {
        return @intCast(self.id);
    }

    pub fn __gc(self: *Resource) void {
        gc_calls[self.id] += 1;
    }

    fn finalize(self: *Resource, _: std.mem.Allocator) void {
        finalizer_calls[self.id] += 1;
    }
};

/// Second userdata type, exposed as `other`, for type confusion fixtures.
const Other = struct {
    number: f64 = 1.5,

    pub fn get(self: *Other) f64 {
        return self.number;
    }
};

fn hostCall(ctx: *api.Context) !void {
    var function = try ctx.arg(0, api.Function);
    defer function.deinit();
    try function.call(.{}, void);
    try ctx.returnValues(.{});
}

fn hostLoad(ctx: *api.Context) !void {
    const source = try ctx.arg(0, []const u8);
    var function = ctx.state().loadString(source, .{ .name = "=host_load" }) catch |err| switch (err) {
        error.LuaError => {
            try ctx.returnValues(.{false});
            return;
        },
        else => return err,
    };
    defer function.deinit();
    try ctx.returnValues(.{true});
}

const ChildResult = struct {
    outcome: []const u8 = "none",
    message_buffer: [512]u8 = undefined,
    message_len: usize = 0,
    peak: usize = 0,
    live: usize = 0,
    output: u64 = 0,
    latency_ms: i64 = -1,
};

const Watchdog = struct {
    io: std.Io,
    handle: api.InterruptHandle,
    delay_ms: u32,
    fired_at: std.atomic.Value(i64) = .init(0),

    fn run(self: *Watchdog) void {
        self.io.sleep(std.Io.Duration.fromMilliseconds(self.delay_ms), .awake) catch return;
        self.fired_at.store(nowNanoseconds(self.io), .release);
        self.handle.interrupt();
    }
};

fn nowNanoseconds(io: std.Io) i64 {
    return @intCast(std.Io.Timestamp.now(io, .awake).nanoseconds);
}

fn recordLastError(lua: *api.State, result: *ChildResult) void {
    var out: std.Io.Writer.Allocating = .init(lua.allocator());
    defer out.deinit();
    lua.writeError(error.LuaError, &out.writer) catch return recordError(result, "?");
    recordError(result, out.written());
}

fn recordError(result: *ChildResult, message: []const u8) void {
    result.outcome = "error";
    result.message_len = @min(message.len, result.message_buffer.len);
    @memcpy(result.message_buffer[0..result.message_len], message[0..result.message_len]);
}

const ChildArgs = struct {
    io: std.Io,
    source: []const u8,
    meta: Metadata,
    stack_bytes: usize,
    result: *ChildResult,
    failure: *?anyerror,
};

fn childThread(args: ChildArgs) void {
    runScript(args) catch |err| {
        args.failure.* = err;
    };
}

const FaultRun = struct { allocations: usize, leaked: usize };

fn runUnderFaults(args: ChildArgs, fail_at: usize, sticky: bool, stress: bool) !FaultRun {
    var tracking: TrackingAllocator = .{ .child = std.heap.smp_allocator };
    var faults: FaultAllocator = .{ .child = tracking.allocator(), .fail_at = fail_at, .sticky = sticky };
    var sink_buffer: [256]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&sink_buffer);
    const lua = api.State.init(faults.allocator(), .{
        .capabilities = .{ .io = .{ .stdout = &sink.writer, .stderr = &sink.writer } },
        .limits = .{ .max_instructions = 5_000_000, .max_native_stack = args.stack_bytes / 2 },
    }) catch return .{ .allocations = faults.count, .leaked = tracking.live };
    lua.raw_state.gc.stress_collect = stress;
    run: {
        installHostBindings(lua) catch break :run;
        var function = lua.loadString(args.source, .{ .name = "=fixture" }) catch |err| {
            if (err == error.LuaError) lua.writeError(err, &sink.writer) catch break :run;
            break :run;
        };
        defer function.deinit();
        function.call(.{}, void) catch |err| {
            if (err == error.LuaError) if (lua.takeError()) |taken| {
                var lua_error = taken;
                lua_error.deinit();
            };
            break :run;
        };
    }
    const allocations = faults.count;
    faults.armed = false;
    usable: {
        var probe = lua.loadString("local t = {} for i = 1, 100 do t[i] = {i} end return #t", .{ .name = "=probe" }) catch break :usable;
        defer probe.deinit();
        const count = probe.call(.{}, i64) catch |err| {
            if (err == error.LuaError) return error.StateUnusable;
            break :usable;
        };
        if (count != 100) return error.StateCorrupted;
    }
    lua.deinit();
    return .{ .allocations = allocations, .leaked = tracking.live };
}

fn runFaultSweep(args: ChildArgs) !void {
    const clean = try runUnderFaults(args, std.math.maxInt(usize), false, false);
    if (clean.leaked != 0) return error.LeakedWithoutFaults;
    _ = try runUnderFaults(args, std.math.maxInt(usize), false, true);
    for ([_]bool{ false, true }) |sticky| {
        for (0..clean.allocations) |fail_at| {
            const run = try runUnderFaults(args, fail_at, sticky, false);
            if (run.leaked != 0) {
                std.debug.print("{d} bytes leaked failing allocation {d} (sticky {})\n", .{ run.leaked, fail_at, sticky });
                return error.LeakedUnderFaults;
            }
        }
    }
}

fn installHostBindings(lua: *api.State) !void {
    for (0..object_count) |id| {
        var resource = try lua.newUserdata(Resource, .{ .id = id }, .{ .finalizer = Resource.finalize });
        defer resource.deinit();
        try lua.setGlobal(if (id == 0) "res" else "res2", resource);
    }
    var other = try lua.newUserdata(Other, .{}, .{});
    defer other.deinit();
    try lua.setGlobal("other", other);

    var host_call = try lua.newFunction("host_call", hostCall);
    defer host_call.deinit();
    try lua.setGlobal("host_call", host_call);
    var host_load = try lua.newFunction("host_load", hostLoad);
    defer host_load.deinit();
    try lua.setGlobal("host_load", host_load);
}

fn runScript(args: ChildArgs) !void {
    const meta = args.meta;
    if (meta.fault_sweep) try runFaultSweep(args);
    gc_calls = @splat(0);
    finalizer_calls = @splat(0);
    var tracking: TrackingAllocator = .{ .child = std.heap.smp_allocator };
    var sink_buffer: [256]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&sink_buffer);

    const lua = try api.State.init(tracking.allocator(), .{
        .stdlib = if (meta.stdlib == .full) .full else .safe,
        .capabilities = .{ .io = .{ .stdout = &sink.writer, .stderr = &sink.writer } },
        .limits = .{
            .max_memory = meta.max_memory,
            .max_instructions = meta.max_instructions,
            .max_native_stack = args.stack_bytes - @max(args.stack_bytes / 4, native_stack_margin),
            .max_output_bytes = meta.max_output,
        },
        .binary_chunks = meta.binary_chunks,
    });

    try installHostBindings(lua);

    var watchdog: ?Watchdog = null;
    var watchdog_thread: ?std.Thread = null;
    if (meta.interrupt_ms) |delay_ms| {
        watchdog = .{ .io = args.io, .handle = try lua.interruptHandle(), .delay_ms = delay_ms };
        watchdog_thread = try std.Thread.spawn(.{}, Watchdog.run, .{&watchdog.?});
    }

    const result = args.result;
    run: {
        var function = lua.loadString(args.source, .{ .name = "=fixture" }) catch |err| {
            if (err == error.LuaError) recordLastError(lua, result) else result.outcome = @errorName(err);
            break :run;
        };
        defer function.deinit();
        function.callWith(.{}, void, .{ .max_instructions = meta.call_instructions }) catch |err| {
            if (err == error.LuaError) {
                recordLastError(lua, result);
            } else {
                result.outcome = if (err == error.Interrupted) "interrupted" else @errorName(err);
            }
            break :run;
        };
        result.outcome = "ok";
    }
    const finished_at = nowNanoseconds(args.io);
    if (watchdog_thread) |thread| {
        thread.join();
        const fired_at = watchdog.?.fired_at.load(.acquire);
        result.latency_ms = @intCast(@divTrunc(finished_at - fired_at, std.time.ns_per_ms));
    }

    lua.resetInstructionBudget();
    if (lua.loadString("return 1", .{ .name = "=probe" })) |function| {
        var probe = function;
        probe.deinit();
    } else |_| {}
    lua.collect() catch {};
    lua.deinit();

    result.peak = tracking.peak;
    result.live = tracking.live;
    result.output = sink.fullCount();
}

/// Runs one fixture in this process and prints its results for the parent to check.
pub fn runChild(allocator: std.mem.Allocator, io: std.Io, path: []const u8, stack_bytes: usize) !void {
    const source = try Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 << 20));
    defer allocator.free(source);
    const meta = try parseMetadata(source);

    var result: ChildResult = .{};
    var failure: ?anyerror = null;
    const thread = try std.Thread.spawn(.{ .stack_size = stack_bytes }, childThread, .{ChildArgs{
        .io = io,
        .source = source,
        .meta = meta,
        .stack_bytes = stack_bytes,
        .result = &result,
        .failure = &failure,
    }});
    thread.join();
    if (failure) |err| return err;

    var finalizer_min: u32 = std.math.maxInt(u32);
    var finalizer_max: u32 = 0;
    var gc_max: u32 = 0;
    for (finalizer_calls, gc_calls) |finalizers, gcs| {
        finalizer_min = @min(finalizer_min, finalizers);
        finalizer_max = @max(finalizer_max, finalizers);
        gc_max = @max(gc_max, gcs);
    }

    var buffer: [1024]u8 = undefined;
    var writer = File.stdout().writer(io, &buffer);
    const out = &writer.interface;
    try out.print("outcome={s}\npeak={d}\nlive={d}\noutput={d}\nlatency={d}\nfinalizer_min={d}\nfinalizer_max={d}\ngc_max={d}\nmessage={s}\n", .{
        result.outcome,
        result.peak,
        result.live,
        result.output,
        result.latency_ms,
        finalizer_min,
        finalizer_max,
        gc_max,
        result.message_buffer[0..result.message_len],
    });
    try out.flush();
}

/// Writes `count` generated programs into `directory` for the differential harness.
pub fn generatePrograms(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, count: usize, seed: u64) !void {
    try Dir.cwd().createDirPath(io, directory);
    var prng: std.Random.DefaultPrng = .init(seed);
    var random = prng.random();
    const picker = generators.Picker.fromRandom(&random);
    for (0..count) |index| {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        try generators.writeProgram(picker, &out.writer);
        const name = try std.fmt.allocPrint(allocator, "{s}/generated_{d}.lua", .{ directory, index });
        defer allocator.free(name);
        try Dir.cwd().writeFile(io, .{ .sub_path = name, .data = out.written() });
    }
}

const Options = struct {
    path: []const u8 = "tests/sandbox",
    stacks: []const u8 = "8388608,1048576,262144",
    timeout_ms: u64 = 300_000,
    jobs: usize = 0,
    show_output: bool = false,
};

const Case = struct {
    path: []const u8,
    stack_bytes: usize,
    failure: ?[]u8 = null,
};

const Run = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    self_exe: []const u8,
    options: Options,
    cases: []Case,
    out: *std.Io.Writer,
    failed: usize = 0,

    fn runCase(self: *Run, index: usize) anyerror!void {
        const case = &self.cases[index];
        case.failure = try runOneCase(self.allocator, self.io, self.self_exe, case.*, self.options);
    }

    fn reportCase(self: *Run, index: usize) anyerror!void {
        const case = &self.cases[index];
        if (case.failure) |failure| {
            self.failed += 1;
            try self.out.print("FAIL {s} [{d} KiB]: {s}\n", .{ case.path, case.stack_bytes / 1024, failure });
            try self.out.flush();
        }
    }
};

fn field(output: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len > name.len and line[name.len] == '=' and std.mem.startsWith(u8, line, name)) return line[name.len + 1 ..];
    }
    return null;
}

fn intField(output: []const u8, name: []const u8) i64 {
    return std.fmt.parseInt(i64, field(output, name) orelse "0", 10) catch 0;
}

fn runOneCase(allocator: std.mem.Allocator, io: std.Io, self_exe: []const u8, case: Case, options: Options) !?[]u8 {
    const source = try Dir.cwd().readFileAlloc(io, case.path, allocator, .limited(64 << 20));
    defer allocator.free(source);
    const meta = parseMetadata(source) catch return try allocator.dupe(u8, "invalid metadata");
    if (case.stack_bytes < meta.min_stack) return null;

    var stack_arg: [32]u8 = undefined;
    const stack_text = try std.fmt.bufPrint(&stack_arg, "{d}", .{case.stack_bytes});
    const argv = [_][]const u8{ self_exe, "--child", case.path, stack_text };
    var result = try process.runProcess(allocator, io, &argv, .{ .timeout_ms = options.timeout_ms, .max_output_bytes = 1024 * 1024 });
    defer result.deinit(allocator);

    if (result.timed_out) return try allocator.dupe(u8, "timed out");
    if (result.signal) |signal| return try std.fmt.allocPrint(allocator, "killed by signal {d}", .{signal});
    if (result.exit_code != 0) {
        const tail = result.stderr[result.stderr.len -| 400..];
        return try std.fmt.allocPrint(allocator, "exit code {?d}: {s}", .{ result.exit_code, tail });
    }

    const outcome = field(result.stdout, "outcome") orelse "missing";
    const message = field(result.stdout, "message") orelse "";
    if (meta.outcome != .any and !std.mem.eql(u8, outcome, @tagName(meta.outcome))) {
        return try std.fmt.allocPrint(allocator, "expected outcome {s}, got {s}: {s}", .{ @tagName(meta.outcome), outcome, message[0..@min(message.len, 200)] });
    }
    if (meta.message.len != 0 and std.mem.indexOf(u8, message, meta.message) == null) {
        return try std.fmt.allocPrint(allocator, "expected message '{s}', got '{s}'", .{ meta.message, message[0..@min(message.len, 200)] });
    }

    const live = intField(result.stdout, "live");
    if (live != 0) return try std.fmt.allocPrint(allocator, "{d} bytes live after deinit", .{live});
    if (meta.max_memory) |limit| {
        const overhead = 1 << 20;
        const peak = intField(result.stdout, "peak");
        if (peak > limit + overhead) return try std.fmt.allocPrint(allocator, "peak {d} bytes over the {d} byte limit", .{ peak, limit });
    }
    const output = intField(result.stdout, "output");
    if (output > meta.max_output) return try std.fmt.allocPrint(allocator, "{d} output bytes over the {d} byte limit", .{ output, meta.max_output });
    if (meta.latency_ms) |limit| {
        const latency = intField(result.stdout, "latency");
        if (latency > limit) return try std.fmt.allocPrint(allocator, "interrupt took {d} ms", .{latency});
    }
    if (intField(result.stdout, "finalizer_min") != 1 or intField(result.stdout, "finalizer_max") != 1) {
        return try std.fmt.allocPrint(allocator, "host finalizer ran {d} to {d} times", .{ intField(result.stdout, "finalizer_min"), intField(result.stdout, "finalizer_max") });
    }
    const gc_max = intField(result.stdout, "gc_max");
    if (gc_max > 1) return try std.fmt.allocPrint(allocator, "__gc ran {d} times on one object", .{gc_max});
    if (options.show_output) std.debug.print("{s} [{d} KiB]: {s}", .{ case.path, case.stack_bytes / 1024, result.stdout });
    return null;
}

fn parseArgs(args: []const []const u8) !Options {
    var options: Options = .{};
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--stacks=")) {
            options.stacks = arg["--stacks=".len..];
        } else if (std.mem.startsWith(u8, arg, "--timeout-ms=")) {
            options.timeout_ms = try std.fmt.parseInt(u64, arg["--timeout-ms=".len..], 10);
        } else if (std.mem.startsWith(u8, arg, "--jobs=")) {
            options.jobs = try std.fmt.parseInt(usize, arg["--jobs=".len..], 10);
        } else if (std.mem.eql(u8, arg, "--show-output")) {
            options.show_output = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownOption;
        } else {
            options.path = arg;
        }
    }
    return options;
}

fn lessThanString(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

/// Runs every fixture on every stack size. `self_exe` is respawned with `--child`.
pub fn runCli(allocator: std.mem.Allocator, io: std.Io, self_exe: []const u8, args: []const []const u8) !u8 {
    const options = try parseArgs(args);

    var tests = std.ArrayList([]u8).empty;
    defer {
        for (tests.items) |path| allocator.free(path);
        tests.deinit(allocator);
    }
    try fixtures.discoverTests(allocator, io, options.path, ".lua", &tests);
    std.mem.sort([]u8, tests.items, {}, lessThanString);

    var cases = std.ArrayList(Case).empty;
    defer {
        for (cases.items) |case| if (case.failure) |failure| allocator.free(failure);
        cases.deinit(allocator);
    }
    for (tests.items) |path| {
        var stacks = std.mem.tokenizeScalar(u8, options.stacks, ',');
        while (stacks.next()) |stack| {
            try cases.append(allocator, .{ .path = path, .stack_bytes = try std.fmt.parseInt(usize, stack, 10) });
        }
    }

    var buffer: [4096]u8 = undefined;
    var writer = File.stdout().writer(io, &buffer);
    const out = &writer.interface;
    var run: Run = .{ .allocator = allocator, .io = io, .self_exe = self_exe, .options = options, .cases = cases.items, .out = out };
    try parallel.forEachOrdered(allocator, io, options.jobs, cases.items.len, &run, Run.runCase, Run.reportCase);

    try out.print("summary:\n  cases={d}\n  failed={d}\n", .{ cases.items.len, run.failed });
    try out.flush();
    return if (run.failed == 0) 0 else 1;
}

test "metadata parses limits and stops at the first code line" {
    const meta = try parseMetadata(
        \\-- outcome: error
        \\-- message: instruction limit exceeded
        \\-- max-memory: none
        \\-- max-instructions: 500
        \\local outcome = 1
    );
    try std.testing.expectEqual(Outcome.@"error", meta.outcome);
    try std.testing.expectEqualStrings("instruction limit exceeded", meta.message);
    try std.testing.expectEqual(@as(?usize, null), meta.max_memory);
    try std.testing.expectEqual(@as(?u64, 500), meta.max_instructions);
    try std.testing.expectError(error.InvalidMetadata, parseMetadata("-- nonsense: 1"));
}
