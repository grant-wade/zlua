//! Run: zig build run-example -Doptimize=ReleaseFast -- snapshot_reset
const std = @import("std");
const zlua = @import("zlua");
const Timestamp = std.Io.Timestamp;
const iterations = 100;
const warmup = 10;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var lua: ?zlua.State = try initialize(allocator);
    defer if (lua) |*state| state.deinit();

    const capture_start = Timestamp.now(init.io, .awake);
    var snapshot = try lua.?.snapshot(allocator);
    defer snapshot.deinit();
    const capture_ns = elapsed(init.io, capture_start);
    var worker = try snapshot.newState(allocator);
    defer worker.deinit();

    var reset_samples: [iterations]u64 = undefined;
    var rebuild_samples: [iterations]u64 = undefined;
    for (0..warmup + iterations) |i| {
        // Alternate order to reduce systematic timing bias. Both paths start
        // with identical initialized state and run the same request, untimed.
        for (0..2) |j| {
            const reset = (i + j) % 2 == 0;
            try call(if (reset) &worker else &lua.?, "request");
            const start = Timestamp.now(init.io, .awake);
            if (reset) {
                try worker.reset();
            } else {
                lua.?.deinit();
                lua = null; // Keep cleanup safe if initialization fails.
                lua = try initialize(allocator);
            }
            const ns = elapsed(init.io, start);
            // Reacquire handles after reset; previous handles are invalidated.
            try call(if (reset) &worker else &lua.?, "verify_baseline");
            if (i >= warmup) {
                if (reset) reset_samples[i - warmup] = ns else rebuild_samples[i - warmup] = ns;
            }
        }
    }
    std.mem.sort(u64, &reset_samples, {}, std.sort.asc(u64));
    std.mem.sort(u64, &rebuild_samples, {}, std.sort.asc(u64));
    const reset_ns = reset_samples[iterations / 2];
    const rebuild_ns = rebuild_samples[iterations / 2];
    std.debug.print(
        "128 host functions, 16 initialized modules, full libraries\n" ++
            "{d} samples per path after {d} warmups\n" ++
            "one-time snapshot: {d:.3} ms\n" ++
            "snapshot reset:    {d:.3} ms median\n" ++
            "deinit + rebuild:  {d:.3} ms median\n" ++
            "speedup: {d:.2}x\n",
        .{ iterations, warmup, ms(capture_ns), ms(reset_ns), ms(rebuild_ns), @as(f64, @floatFromInt(rebuild_ns)) / @as(f64, @floatFromInt(reset_ns)) },
    );
    if (rebuild_ns > reset_ns) {
        std.debug.print("capture amortized after approximately {d} resets\n", .{
            try std.math.divCeil(u64, capture_ns, rebuild_ns - reset_ns),
        });
    } else {
        std.debug.print("reset did not beat rebuilding on this run\n", .{});
    }
}

fn initialize(allocator: std.mem.Allocator) !zlua.State {
    var lua = try zlua.State.init(allocator, .{ .stdlib = .full });
    errdefer lua.deinit();
    for (0..128) |i| {
        var buffer: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&buffer, "host_{d}", .{i});
        var callback = try lua.registerTyped(name, hostScale);
        defer callback.deinit();
        try lua.setGlobal(name, callback);
    }
    for (0..16) |i| {
        var buffer: [32]u8 = undefined;
        const path = try std.fmt.bufPrint(&buffer, "service{d}.lua", .{i});
        try lua.addMemoryFile(path,
            \\local M = {weights = {}, calls = 0}
            \\-- Precompute a small lookup table from a larger training dataset.
            \\for bucket = 1, 64 do
            \\    local sum = 0
            \\    for sample = 1, 256 do
            \\        sum = sum + math.sqrt(bucket * sample)
            \\    end
            \\    M.weights[bucket] = sum / 256
            \\end
            \\function M.run(value)
            \\    M.calls = M.calls + 1
            \\    return host_0(value) + M.weights[1]
            \\end
            \\return M
        );
    }
    try lua.doString(
        \\services = {}
        \\for i = 0, 15 do services[i + 1] = require('service' .. i) end
        \\function verify_baseline()
        \\    assert(temporary == nil)
        \\    for i = 0, 127 do assert(_G['host_' .. i](21) == 42) end
        \\    for i, service in ipairs(services) do
        \\        assert(service.calls == 0 and service.weights[1] > 0)
        \\        assert(service == package.loaded['service' .. (i - 1)])
        \\    end
        \\end
        \\function request()
        \\    verify_baseline()
        \\    temporary = {}
        \\    for i, service in ipairs(services) do
        \\        temporary[i] = service.run(i)
        \\        assert(service.calls == 1)
        \\        service.weights[1] = -1
        \\    end
        \\    host_127 = nil
        \\    package.loaded.service0 = nil
        \\end
    , .{ .name = "=application_init" });
    return lua;
}

fn hostScale(value: i64) i64 {
    return value * 2;
}

fn call(lua: *zlua.State, name: []const u8) !void {
    var function = try lua.getGlobal(name, zlua.Function);
    defer function.deinit();
    try function.call(.{}, void);
}

fn elapsed(io: std.Io, start: Timestamp) u64 {
    return @intCast(start.durationTo(Timestamp.now(io, .awake)).toNanoseconds());
}

fn ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}
