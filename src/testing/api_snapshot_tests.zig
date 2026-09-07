const std = @import("std");
const api = @import("../api.zig");
const a = std.testing.allocator;

test "snapshot preserves suspended coroutine continuations hooks and open upvalues" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.doString(
        \\closed = 0; hits = 0
        \\co = coroutine.create(function(...)
        \\  local args = {...}
        \\  local n = 10
        \\  local closer <close> = setmetatable({}, {__close = function() closed = closed + 1 end})
        \\  function read_n() return n end
        \\  local ok, x = pcall(function() return coroutine.yield(n, table.unpack(args)) end)
        \\  assert(ok); n = n + x
        \\  return n, table.unpack(args)
        \\end)
        \\debug.sethook(co, function() hits = hits + 1 end, "l", 3)
        \\local ok, n, x, y = coroutine.resume(co, 7, 8)
        \\assert(ok and n == 10 and x == 7 and y == 8)
    , .{});
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    for (0..3) |_| {
        try lua.doString(
            \\assert(read_n() == 10 and closed == 0)
            \\local before = hits
            \\local ok, n, x, y = coroutine.resume(co, 5)
            \\assert(ok and n == 15 and x == 7 and y == 8)
            \\assert(read_n() == 15 and closed == 1 and hits > before)
        , .{});
        try lua.reset(&checkpoint);
    }
}

test "snapshot survives origin and restores modules files iterators streams errors and random state" {
    var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .io = .{ .stdin = "first\nsecond\n" } } });
    try lua.addMemoryFile("m.lua", "return {value = 23}");
    try lua.addMemoryFile("data", "abc\ndef\n");
    try lua.doString(
        \\m = require('m'); m.self = m
        \\file = assert(io.open('data')); assert(file:read('l') == 'abc')
        \\iter = string.gmatch('one two three', '%w+'); assert(iter() == 'one')
        \\assert(io.read('l') == 'first'); print('captured'); io.stderr:write('err')
        \\math.randomseed(123, 456); collectgarbage('stop')
    , .{});
    try std.testing.expectError(error.LuaError, lua.doString("error({message = 'kept'})", .{}));
    const count = lua.instructionBudget().used;
    var checkpoint = try lua.snapshot(a);
    lua.deinit();
    defer checkpoint.deinit();
    var left = try checkpoint.clone(a);
    defer left.deinit();
    var right = try checkpoint.clone(a);
    defer right.deinit();
    try std.testing.expectEqual(count, left.instructionBudget().used);
    try std.testing.expect(!left.raw_state.gc_running);
    try std.testing.expectEqualStrings("captured\n", left.raw_state.stdout.items);
    try std.testing.expectEqualStrings("err", left.raw_state.stderr.items);
    var err = left.takeErrorValue().?;
    defer err.deinit();
    var ev = try err.value();
    defer ev.deinit();
    try std.testing.expectEqualStrings("kept", try ev.table.get("message", []const u8));
    const check =
        \\assert(require('m') == m and m.self == m and m.value == 23)
        \\assert(file:read('l') == 'def'); assert(iter() == 'two')
        \\assert(io.read('l') == 'second'); r = math.random()
    ;
    try left.doString(check, .{});
    try right.doString(check, .{});
    try std.testing.expectEqual(try left.getGlobal("r", f64), try right.getGlobal("r", f64));
    try left.reset(&checkpoint);
    try left.doString(check, .{});
}

test "snapshot handle generations cross state arguments environments and dispatch" {
    const Host = struct {
        fn set(ctx: *api.Context) !void {
            try ctx.state().setGlobal("destination", true);
        }
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var cb = try lua.register("host", Host.set);
    defer cb.deinit();
    try lua.setGlobal("host", cb);
    var function = try lua.loadString("return ...", .{});
    defer function.deinit();
    var table = try lua.createTable(.{});
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    var other = try checkpoint.clone(a);
    defer other.deinit();
    try std.testing.expectError(error.InvalidHandle, other.setGlobal("foreign", table));
    try std.testing.expectError(error.InvalidHandle, other.loadString("", .{ .environment = table }));
    var other_function = try other.loadString("return ...", .{});
    defer other_function.deinit();
    try std.testing.expectError(error.InvalidHandle, other_function.call(.{table}, void));
    try other.doString("host(); assert(destination)", .{});
    try std.testing.expectEqual(api.Value.nil, try lua.getGlobal("destination", api.Value));
    try lua.reset(&checkpoint);
    var reused = try lua.createTable(.{});
    defer reused.deinit();
    table.deinit(); // Must not release the reused root slot.
    try reused.set("alive", true);
    try lua.collect();
    try std.testing.expect(try reused.get("alive", bool));
    try std.testing.expectError(error.InvalidHandle, function.call(.{}, void));
    try std.testing.expectError(error.InvalidHandle, cb.call(.{}, void));
    try std.testing.expectError(error.InvalidHandle, lua.setGlobal("old", function));
}

const Payload = struct {
    value: i64,
    finalizers: *usize,
    disposals: *usize,
    fail: *bool,
    fn finalize(self: *Payload) void {
        self.finalizers.* += 1;
    }
    fn copy(allocator: std.mem.Allocator, self: *const Payload) !*Payload {
        if (self.fail.*) return error.PayloadCopyFailed;
        const p = try allocator.create(Payload);
        p.* = self.*;
        return p;
    }
    fn dispose(allocator: std.mem.Allocator, self: *Payload) void {
        self.disposals.* += 1;
        allocator.destroy(self);
    }
};

test "snapshot hooked payloads are independent and copy failures are atomic" {
    var finals: usize = 0;
    var disposals: usize = 0;
    var fail = false;
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var ud = try lua.newUserdata(Payload, .{ .value = 1, .finalizers = &finals, .disposals = &disposals, .fail = &fail }, .{ .finalizer = Payload.finalize, .snapshot = .{ .copy = Payload.copy, .dispose = Payload.dispose } });
    defer ud.deinit();
    try lua.setGlobal("u", ud);
    var checkpoint = try lua.snapshot(a);
    (try ud.ptr()).value = 9;
    fail = true;
    try std.testing.expectError(error.PayloadCopyFailed, lua.reset(&checkpoint));
    try std.testing.expectEqual(@as(i64, 9), (try ud.ptr()).value);
    try std.testing.expectEqual(@as(usize, 0), finals);
    fail = false;
    var clone = try checkpoint.clone(a);
    var cloned = try clone.getGlobal("u", api.Userdata(Payload));
    try std.testing.expectEqual(@as(i64, 1), (try cloned.ptr()).value);
    (try cloned.ptr()).value = 20;
    cloned.deinit();
    clone.deinit();
    try std.testing.expectEqual(@as(usize, 1), finals);
    try std.testing.expectEqual(@as(usize, 1), disposals);
    checkpoint.deinit();
    try std.testing.expectEqual(@as(usize, 1), finals);
    // The source still retains the checkpoint as its active baseline.
    try std.testing.expectEqual(@as(usize, 1), disposals);
}

test "snapshot hookless payload retains allocator and finalizes once in every destruction order" {
    const orders = [_][3]usize{ .{ 0, 1, 2 }, .{ 0, 2, 1 }, .{ 1, 0, 2 }, .{ 1, 2, 0 }, .{ 2, 0, 1 }, .{ 2, 1, 0 } };
    for (orders) |order| {
        var finals: usize = 0;
        var disposals: usize = 0;
        var fail = false;
        var origin = try api.State.init(a, .{ .limits = .{ .max_memory = 4 * 1024 * 1024 } });
        var ud = try origin.newUserdata(Payload, .{ .value = 1, .finalizers = &finals, .disposals = &disposals, .fail = &fail }, .{ .finalizer = Payload.finalize });
        try origin.setGlobal("u", ud);
        const pointer = try ud.ptr();
        ud.deinit();
        var checkpoint = try origin.snapshot(a);
        var clone = try checkpoint.clone(a);
        var cloned = try clone.getGlobal("u", api.Userdata(Payload));
        try std.testing.expectEqual(pointer, try cloned.ptr());
        cloned.deinit();
        for (order, 0..) |which, index| {
            switch (which) {
                0 => origin.deinit(),
                1 => checkpoint.deinit(),
                2 => clone.deinit(),
                else => unreachable,
            }
            try std.testing.expectEqual(@as(usize, if (index == 2) 1 else 0), finals);
        }
    }
}

test "snapshot weak entries finalizer order and host roots are isolated" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\collectgarbage('stop'); order = ''
        \\weak = setmetatable({}, {__mode='v'})
        \\for i=1,3 do local t = setmetatable({}, {__gc=function() order=order..i end}); weak[i]=t end
    , .{});
    var unrooted = try lua.createTable(.{});
    const extra = unrooted.ref.index;
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    try lua.doString("collectgarbage()", .{});
    const expected = try a.dupe(u8, try lua.getGlobal("order", []const u8));
    defer a.free(expected);
    try std.testing.expect(expected.len == 3);
    try lua.reset(&checkpoint);
    unrooted.deinit();
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.activeRootCount());
    try std.testing.expectEqual(@import("../runtime.zig").Value.nil, lua.raw_state.rootedValue(extra));
    try lua.doString("collectgarbage()", .{});
    try std.testing.expectEqualStrings(expected, try lua.getGlobal("order", []const u8));
    try lua.doString("collectgarbage(); assert(next(weak) == nil)", .{});
}

test "snapshot rejects execution" {
    const Host = struct {
        fn busy(ctx: *api.Context) !void {
            try std.testing.expectError(error.SnapshotBusy, ctx.state().snapshot(a));
        }
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var cb = try lua.register("busy", Host.busy);
    defer cb.deinit();
    try cb.call(.{}, void);
}

fn allocationFixture() !api.State {
    var lua = try api.State.init(a, .{});
    errdefer lua.deinit();
    try lua.addMemoryFile("m.lua", "return 42");
    try lua.doString("collectgarbage('stop'); t = {}; t[t] = t; co = coroutine.create(function(...) local n = 2; function f() return n end; coroutine.yield(...); return n end); coroutine.resume(co, 3, 4)", .{});
    return lua;
}

test "snapshot capture and clone allocation failures release every partial graph" {
    var lua = try allocationFixture();
    defer lua.deinit();
    try std.testing.checkAllAllocationFailures(a, struct {
        fn run(allocator: std.mem.Allocator, state: *api.State) !void {
            var checkpoint = try state.snapshot(allocator);
            defer checkpoint.deinit();
            // The source retains its baseline. Release the failing allocator's
            // storage before the allocator itself leaves scope.
            var stable = try state.snapshot(a);
            stable.deinit();
        }
    }.run, .{&lua});
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    try std.testing.checkAllAllocationFailures(a, struct {
        fn run(allocator: std.mem.Allocator, image: *const api.Snapshot) !void {
            var clone = try image.clone(allocator);
            defer clone.deinit();
        }
    }.run, .{&checkpoint});
}

test "snapshot reset allocation failures leave destination handles and allocator unchanged" {
    var source = try allocationFixture();
    defer source.deinit();
    var checkpoint = try source.snapshot(a);
    defer checkpoint.deinit();
    var offset: usize = 0;
    while (true) : (offset += 1) {
        var failing = std.testing.FailingAllocator.init(a, .{});
        var lua = try api.State.init(failing.allocator(), .{ .stdlib = .none });
        var table = try lua.createTable(.{});
        try table.set("x", 42);
        const generation = lua.generation;
        failing.fail_index = failing.alloc_index + offset;
        const result = lua.reset(&checkpoint);
        failing.fail_index = std.math.maxInt(usize);
        if (result) |_| {
            table.deinit();
            lua.deinit();
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(generation, lua.generation);
            try std.testing.expectEqual(@as(i64, 42), try table.get("x", i64));
            table.deinit();
            lua.deinit();
        }
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

test "snapshot bounded reset requires temporary headroom and keeps host results freeable" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var chunk = try lua.loadString("return 'owned'", .{});
    defer chunk.deinit();
    const message = try lua.errorMessage();
    const original_allocator = lua.allocator();
    defer original_allocator.free(message);
    lua.raw_state.options.max_memory = 1;
    var limited = try lua.snapshot(a);
    defer limited.deinit();
    lua.raw_state.options.max_memory = 4 * 1024 * 1024;
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    try std.testing.expectError(error.OutOfMemory, lua.reset(&limited));
    try std.testing.expectEqualStrings("owned", try chunk.call(.{}, []const u8));
    try lua.reset(&checkpoint);
    try std.testing.expectEqual(original_allocator.ptr, lua.allocator().ptr);
}

test "snapshot resumes xpcall handler yields and to-be-closed coroutine frames" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\closed = 0
        \\co = coroutine.create(function()
        \\  local x <close> = setmetatable({}, {__close=function() closed=closed+1 end})
        \\  return xpcall(function() error('failure') end, function(e) coroutine.yield('handler'); return e end)
        \\end)
        \\local ok, v = coroutine.resume(co); assert(ok and v == 'handler')
    , .{});
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    for (0..2) |_| {
        try lua.doString("local ok, success, err = coroutine.resume(co); assert(ok and not success and string.find(err, 'failure')); assert(closed == 1)", .{});
        try lua.reset(&checkpoint);
        try std.testing.expectEqual(@as(i64, 0), try lua.getGlobal("closed", i64));
    }
    try lua.doString("assert(coroutine.close(co)); assert(closed == 1)", .{});
}

test "snapshot restores instruction limits and GC tuning" {
    var lua = try api.State.init(a, .{ .limits = .{ .max_instructions = 200 } });
    defer lua.deinit();
    try lua.doString("function exhaust() while true do end end; collectgarbage('incremental'); collectgarbage('stop')", .{});
    lua.raw_state.setGcParam(.pause, 333);
    const used = lua.instructionBudget().used;
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    for (0..2) |_| {
        var function = try lua.getGlobal("exhaust", api.Function);
        try std.testing.expectError(error.LuaError, function.call(.{}, void));
        function.deinit();
        lua.raw_state.setGcParam(.pause, 100);
        try lua.reset(&checkpoint);
        try std.testing.expectEqual(used, lua.instructionBudget().used);
        try std.testing.expectEqual(@as(?u64, 200), lua.instructionBudget().limit);
        try std.testing.expectEqual(@as(i64, 333), lua.raw_state.gcParam(.pause));
        try std.testing.expectEqual(@import("../runtime.zig").GcMode.incremental, lua.raw_state.gc_mode);
        try std.testing.expect(!lua.raw_state.gc_running);
    }
}

test "snapshot userdata copy allocation failures never run application finalizers" {
    var finals: usize = 0;
    var disposals: usize = 0;
    var fail = false;
    var lua = try api.State.init(a, .{ .stdlib = .none });
    defer lua.deinit();
    var ud = try lua.newUserdata(Payload, .{ .value = 1, .finalizers = &finals, .disposals = &disposals, .fail = &fail }, .{ .finalizer = Payload.finalize, .snapshot = .{ .copy = Payload.copy, .dispose = Payload.dispose } });
    defer ud.deinit();
    try lua.setGlobal("u", ud);
    // A callback and owned file force fallible allocations after payload copy.
    var cb = try lua.registerTyped("identity", struct {
        fn identity(v: i64) i64 {
            return v;
        }
    }.identity);
    defer cb.deinit();
    try lua.setGlobal("identity", cb);
    try lua.addMemoryFile("file", "bytes");
    try std.testing.checkAllAllocationFailures(a, struct {
        fn run(allocator: std.mem.Allocator, state: *api.State) !void {
            var checkpoint = try state.snapshot(allocator);
            defer checkpoint.deinit();
            // The source retains its baseline. Release the failing allocator's
            // storage before the allocator itself leaves scope.
            var stable = try state.snapshot(a);
            stable.deinit();
        }
    }.run, .{&lua});
    try std.testing.expectEqual(@as(usize, 0), finals);
    try std.testing.expect(disposals > 0);
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    try std.testing.checkAllAllocationFailures(a, struct {
        fn run(allocator: std.mem.Allocator, image: *const api.Snapshot) !void {
            var clone = try image.clone(allocator);
            defer clone.deinit();
        }
    }.run, .{&checkpoint});
    // checkAllAllocationFailures first runs one successful clone for sizing.
    try std.testing.expectEqual(@as(usize, 1), finals);
}

test "snapshot borrowed userdata and deep owned userdata hooks" {
    const Buffer = struct {
        bytes: []u8,
        fn copy(allocator: std.mem.Allocator, self: *const @This()) !*@This() {
            const p = try allocator.create(@This());
            errdefer allocator.destroy(p);
            p.* = .{ .bytes = try allocator.dupe(u8, self.bytes) };
            return p;
        }
        fn dispose(allocator: std.mem.Allocator, self: *@This()) void {
            allocator.free(self.bytes);
            allocator.destroy(self);
        }
    };
    var storage = [_]u8{ 1, 2, 3 };
    var backing = Buffer{ .bytes = &storage };
    var lua = try api.State.init(a, .{});
    var shared = try lua.newUserdataPtr(Buffer, &backing, .{});
    try lua.setGlobal("shared", shared);
    shared.deinit();
    var owned = try lua.newUserdataPtr(Buffer, &backing, .{ .snapshot = .{ .copy = Buffer.copy, .dispose = Buffer.dispose } });
    try lua.setGlobal("owned", owned);
    owned.deinit();
    var checkpoint = try lua.snapshot(a);
    lua.deinit();
    var clone = try checkpoint.clone(a);
    checkpoint.deinit();
    defer clone.deinit();
    var shared_clone = try clone.getGlobal("shared", api.Userdata(Buffer));
    defer shared_clone.deinit();
    var owned_clone = try clone.getGlobal("owned", api.Userdata(Buffer));
    defer owned_clone.deinit();
    storage[0] = 9;
    try std.testing.expectEqual(@as(u8, 9), (try shared_clone.ptr()).bytes[0]);
    try std.testing.expectEqual(@as(u8, 1), (try owned_clone.ptr()).bytes[0]);
}

test "snapshot successful reset disposes copied payloads without semantic finalization" {
    var finals: usize = 0;
    var disposals: usize = 0;
    var fail = false;
    var lua = try api.State.init(a, .{ .stdlib = .none });
    var ud = try lua.newUserdata(Payload, .{ .value = 1, .finalizers = &finals, .disposals = &disposals, .fail = &fail }, .{ .finalizer = Payload.finalize, .snapshot = .{ .copy = Payload.copy, .dispose = Payload.dispose } });
    try lua.setGlobal("u", ud);
    ud.deinit();
    var checkpoint = try lua.snapshot(a);
    try lua.reset(&checkpoint);
    // Original storage keeps its original finalizer/destructor contract.
    try std.testing.expectEqual(@as(usize, 1), finals);
    try lua.reset(&checkpoint);
    try std.testing.expectEqual(@as(usize, 1), finals);
    try std.testing.expectEqual(@as(usize, 1), disposals);
    lua.deinit();
    try std.testing.expectEqual(@as(usize, 2), finals);
    checkpoint.deinit();
    try std.testing.expectEqual(@as(usize, 2), finals);
    try std.testing.expectEqual(@as(usize, 3), disposals);
}

test "snapshot retains exposed host thread identities after host frames expire" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    try lua.doString("main = coroutine.running(); t = {[main] = main}; co = coroutine.create(function() coroutine.yield(coroutine.running()) end); local ok, thread = coroutine.resume(co); assert(ok and thread == co)", .{});
    var checkpoint = try lua.snapshot(a);
    lua.deinit();
    var clone = try checkpoint.clone(a);
    checkpoint.deinit();
    defer clone.deinit();
    try clone.doString("assert(type(main) == 'thread' and t[main] == main); assert(coroutine.status(main) == 'dead'); assert(coroutine.resume(co))", .{});
}

test "snapshot retains native diagnostic strings in suspended live locals" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.doString("co = coroutine.create(function() local ok, msg = pcall(dofile, 'disabled'); assert(not ok and type(msg) == 'string'); coroutine.yield(); return msg end); assert(coroutine.resume(co))", .{});
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    try lua.reset(&checkpoint);
    try lua.doString("local ok, msg = coroutine.resume(co); assert(ok and msg == 'filesystem access disabled')", .{});
}

test "snapshot workers share immutable bytecode but keep closures and caches private" {
    var source = try api.State.init(a, .{});
    try source.doString("function f() return 'retained-constant' end", .{});
    var checkpoint = try source.snapshot(a);
    source.deinit();
    var left = try checkpoint.clone(a);
    defer left.deinit();
    var right = try checkpoint.clone(a);
    defer right.deinit();
    checkpoint.deinit();
    var lf = try left.getGlobal("f", api.Function);
    defer lf.deinit();
    var rf = try right.getGlobal("f", api.Function);
    defer rf.deinit();
    const lc = left.raw_state.rootedValue(lf.ref.index).closure;
    const rc = right.raw_state.rootedValue(rf.ref.index).closure;
    try std.testing.expect(lc != rc);
    try std.testing.expectEqual(lc.proto, rc.proto);
    try std.testing.expectEqualStrings("retained-constant", try lf.call(.{}, []const u8));
    try std.testing.expectEqualStrings("retained-constant", try rf.call(.{}, []const u8));
    try std.testing.expect(lc.constants.?.ptr != rc.constants.?.ptr);
}

test "snapshot recapture preserves old bytecode owner and captures modified worker" {
    var source = try api.State.init(a, .{});
    try source.doString("local n = 1; function f() n = n + 1; return n end", .{});
    var original = try source.snapshot(a);
    source.deinit();
    var worker = try original.clone(a);
    original.deinit();
    try worker.doString("assert(f() == 2); function g() return f() end", .{});
    var captured = try worker.snapshot(a);
    // Capturing changed the baseline, but f still borrows the old bytecode.
    try worker.doString("assert(g() == 3)", .{});
    var second = try captured.clone(a);
    captured.deinit();
    worker.deinit();
    defer second.deinit();
    try second.doString("assert(g() == 3); collectgarbage(); assert(g() == 4)", .{});
}

test "snapshot retained identity survives wrapper moves switching and destruction orders" {
    const orders = [_][3]usize{ .{ 0, 1, 2 }, .{ 0, 2, 1 }, .{ 1, 0, 2 }, .{ 1, 2, 0 }, .{ 2, 0, 1 }, .{ 2, 1, 0 } };
    for (orders) |order| {
        var source = try api.State.init(a, .{});
        try source.doString("function f() return 1 end", .{});
        var first = try source.snapshot(a);
        var moved = first;
        first = undefined;
        var worker = try moved.clone(a);
        try source.doString("function f() return 2 end", .{});
        var second = try source.snapshot(a);
        for (0..4) |_| {
            try worker.reset(&second);
            try worker.doString("assert(f() == 2)", .{});
            try worker.reset(&moved);
            try worker.doString("assert(f() == 1)", .{});
        }
        second.deinit();
        for (order) |which| switch (which) {
            0 => source.deinit(),
            1 => moved.deinit(),
            2 => worker.deinit(),
            else => unreachable,
        };
    }
}

test "snapshot using the state allocator retains its accounting infrastructure" {
    var source = try api.State.init(a, .{});
    try source.doString("function f() return 42 end", .{});
    var checkpoint = try source.snapshot(source.allocator());
    source.deinit();
    var worker = try checkpoint.clone(a);
    checkpoint.deinit();
    defer worker.deinit();
    try worker.doString("assert(f() == 42)", .{});
}

test "shared bytecode clone agrees with independent graph copy" {
    var source = try api.State.init(a, .{ .stdlib = .full });
    defer source.deinit();
    try source.doString(
        \\collectgarbage('stop')
        \\t = {}; t[t] = t; alias = t
        \\weak = setmetatable({}, {__mode='v'}); weak[1] = {}
        \\local n = 5; function f() n = n + 1; return n end
        \\co = coroutine.create(function() local x = f(); coroutine.yield(x); return f() end)
        \\assert(coroutine.resume(co))
    , .{});
    var checkpoint = try source.snapshot(a);
    defer checkpoint.deinit();
    var shared = try checkpoint.clone(a);
    defer shared.deinit();
    var copied = api.State{
        .base_allocator = a,
        .raw_state = try @import("../runtime/snapshot.zig").copy(&source.raw_state, a, null, null),
    };
    defer copied.deinit();
    const operations = [_][]const u8{
        "assert(t == alias and t[t] == t); t.changed = f()",
        "debug.setupvalue(f, 1, 100); local ok, n = coroutine.resume(co); assert(ok); result = n",
        "collectgarbage(); assert(next(weak) == nil); result = result + f(); print(result, t.changed)",
    };
    for (operations) |operation| {
        try shared.doString(operation, .{});
        try copied.doString(operation, .{});
        try std.testing.expectEqualStrings(copied.raw_state.stdout.items, shared.raw_state.stdout.items);
        try std.testing.expectEqual(copied.instructionBudget().used, shared.instructionBudget().used);
    }
}

test "retained snapshots have bounded worker memory over one thousand resets" {
    const CountingAllocator = @import("bench/allocation.zig").CountingAllocator;
    var counter = CountingAllocator{ .backing = a };
    var source = try api.State.init(a, .{});
    try source.doString("data = {value=1}; function work() data.value=2; extra={data, data} end", .{});
    var checkpoint = try source.snapshot(a);
    source.deinit();
    var worker = try checkpoint.clone(counter.allocator());
    try worker.reset(&checkpoint);
    // Host root slots retain capacity independently of managed heap rollback.
    var warmup = try worker.getGlobal("work", api.Function);
    try warmup.call(.{}, void);
    warmup.deinit();
    try worker.reset(&checkpoint);
    const baseline_bytes = counter.live_bytes;
    for (0..1000) |_| {
        var work = try worker.getGlobal("work", api.Function);
        try work.call(.{}, void);
        work.deinit();
        try worker.reset(&checkpoint);
        try std.testing.expectEqual(baseline_bytes, counter.live_bytes);
    }
    checkpoint.deinit();
    worker.deinit();
    try std.testing.expectEqual(@as(u64, 0), counter.live_bytes);
}

test "incremental no-op reset allocates nothing and visits no heap objects" {
    const CountingAllocator = @import("bench/allocation.zig").CountingAllocator;
    for ([_]usize{ 16, 4096 }) |size| {
        var counter = CountingAllocator{ .backing = a };
        var lua = try api.State.init(counter.allocator(), .{});
        defer lua.deinit();
        const script = try std.fmt.allocPrint(a, "collectgarbage('stop'); data={{}}; for i=1,{d} do data[i]={{i}} end", .{size});
        defer a.free(script);
        try lua.doString(script, .{});
        const identity = lua.raw_state.getGlobal("data").table;
        var checkpoint = try lua.snapshot(a);
        defer checkpoint.deinit();
        const allocations = counter.allocations;
        const resizes = counter.resizes;
        for (0..10) |_| {
            try lua.reset(&checkpoint);
            try std.testing.expectEqual(allocations, counter.allocations);
            try std.testing.expectEqual(resizes, counter.resizes);
            try std.testing.expectEqual(identity, lua.raw_state.getGlobal("data").table);
            try std.testing.expectEqual(@as(usize, 0), lua.raw_state.rollback.?.last_restored_objects);
        }
        const child = identity.get(.{ .integer = 1 }).table;
        try child.set(lua.allocator(), .{ .integer = 1 }, .{ .integer = 99 });
        const before_reset = counter.allocations;
        try lua.reset(&checkpoint);
        try std.testing.expectEqual(before_reset, counter.allocations);
        try std.testing.expectEqual(@as(usize, 1), lua.raw_state.rollback.?.last_restored_objects);
        try std.testing.expectEqual(@as(i64, 1), child.get(.{ .integer = 1 }).integer);
    }
}

test "incremental existing writes preserve metamethods aliases keys and debug mutations" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.doString(
        \\collectgarbage('stop'); calls = 0
        \\t = setmetatable({value=1}, {__newindex=function() calls=calls+1 end}); alias=t; keys={[t]=t}
        \\co=coroutine.create(function(...) local x=7; function f() return x end; coroutine.yield(); return x,... end)
        \\assert(coroutine.resume(co, 8))
    , .{});
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    for (0..3) |_| {
        try lua.doString("t.value=2; t.new=3; assert(calls==1 and alias.value==2 and keys[t]==t); debug.setupvalue(f,1,20); assert(f()==20); assert(coroutine.resume(co))", .{});
        try lua.reset(&checkpoint);
        try lua.doString("assert(t.value==1 and calls==0 and f()==7 and coroutine.status(co)=='suspended')", .{});
    }
}

const ScopedPayload = struct {
    value: i64 = 1,
    copies: *usize,
    finals: *usize,
    disposals: *usize,
    fail: *bool,
    fn copy(allocator: std.mem.Allocator, self: *const @This()) !*@This() {
        if (self.fail.*) return error.PayloadCopyFailed;
        const p = try allocator.create(@This());
        p.* = self.*;
        self.copies.* += 1;
        return p;
    }
    fn dispose(allocator: std.mem.Allocator, self: *@This()) void {
        self.disposals.* += 1;
        allocator.destroy(self);
    }
    fn finalize(self: *@This()) void {
        self.finals.* += 1;
        self.value = -100;
    }
    pub fn increment(self: *@This(), amount: i64) void {
        self.value += amount;
    }
    pub fn valueOf(self: *const @This()) i64 {
        return self.value;
    }
    fn read(self: *const @This(), _: void) i64 {
        return self.value;
    }
    fn mutate(self: *@This(), amount: i64) void {
        self.value += amount;
    }
    fn mutateFail(self: *@This(), _: void) !void {
        self.value = 99;
        return error.CallbackFailed;
    }
};

test "scoped userdata copies on first write with atomic failure and unchanged reset" {
    var copies: usize = 0;
    var finals: usize = 0;
    var disposals: usize = 0;
    var fail = false;
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var ud = try lua.newUserdataAuto(ScopedPayload, .{ .copies = &copies, .finals = &finals, .disposals = &disposals, .fail = &fail }, .{ .finalizer = ScopedPayload.finalize, .snapshot = .{ .copy = ScopedPayload.copy, .dispose = ScopedPayload.dispose, .tracking = .scoped } });
    try lua.setGlobal("u", ud);
    try std.testing.expectError(error.ScopedAccessRequired, ud.ptr());
    try std.testing.expectError(error.ScopedAccessRequired, lua.getGlobal("u", *ScopedPayload));
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    const captured_copies = copies;
    ud.deinit();
    for (0..3) |_| try lua.reset(&checkpoint);
    try std.testing.expectEqual(captured_copies, copies);
    ud = try lua.getGlobal("u", api.Userdata(ScopedPayload));
    fail = true;
    try std.testing.expectError(error.PayloadCopyFailed, ud.withMut(@as(i64, 3), ScopedPayload.mutate));
    try std.testing.expectEqual(@as(i64, 1), try ud.withRead({}, ScopedPayload.read));
    fail = false;
    try std.testing.expectError(error.CallbackFailed, ud.withMut({}, ScopedPayload.mutateFail));
    try ud.withMut(@as(i64, 1), ScopedPayload.mutate);
    try std.testing.expectEqual(@as(i64, 100), try ud.withRead({}, ScopedPayload.read));
    try std.testing.expectEqual(captured_copies + 1, copies);
    ud.deinit();
    try lua.reset(&checkpoint);
    try std.testing.expectEqual(captured_copies + 1, copies);
    try lua.doString("assert(u:valueOf()==1); u:increment(4); assert(u:valueOf()==5)", .{});
    try std.testing.expectEqual(captured_copies + 2, copies);
    try lua.reset(&checkpoint);
    var typed = try lua.registerTyped("increment", struct {
        fn call(p: *ScopedPayload) void {
            p.value += 2;
        }
    }.call);
    defer typed.deinit();
    try lua.setGlobal("increment", typed);
    try lua.doString("increment(u); assert(u:valueOf()==3)", .{});
}

test "scoped access blocks snapshots and restores a fresh resource after finalization" {
    var copies: usize = 0;
    var finals: usize = 0;
    var disposals: usize = 0;
    var fail = false;
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var ud = try lua.newUserdata(ScopedPayload, .{ .copies = &copies, .finals = &finals, .disposals = &disposals, .fail = &fail }, .{ .finalizer = ScopedPayload.finalize, .snapshot = .{ .copy = ScopedPayload.copy, .dispose = ScopedPayload.dispose, .tracking = .scoped } });
    try lua.setGlobal("u", ud);
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    const Context = struct { lua: *api.State, checkpoint: *const api.Snapshot };
    try ud.withRead(Context{ .lua = &lua, .checkpoint = &checkpoint }, struct {
        fn call(_: *const ScopedPayload, ctx: Context) !void {
            try std.testing.expectError(error.SnapshotBusy, ctx.lua.snapshot(a));
            try std.testing.expectError(error.SnapshotBusy, ctx.lua.reset(ctx.checkpoint));
        }
    }.call);
    ud.deinit();
    for (0..3) |iteration| {
        try lua.setGlobal("u", null);
        try lua.collect();
        try std.testing.expectEqual(iteration + 1, finals);
        try lua.reset(&checkpoint);
        var restored = try lua.getGlobal("u", api.Userdata(ScopedPayload));
        try std.testing.expectEqual(@as(i64, 1), try restored.withRead({}, ScopedPayload.read));
        restored.deinit();
    }
}

test "first table write allocation failures leave baseline storage and handles intact" {
    var offset: usize = 0;
    while (true) : (offset += 1) {
        var failing = std.testing.FailingAllocator.init(a, .{});
        var lua = try api.State.init(failing.allocator(), .{ .stdlib = .none });
        defer lua.deinit();
        var table = try lua.createTable(.{});
        defer table.deinit();
        try table.set(1, 7);
        try table.set("key", 8);
        var checkpoint = try lua.snapshot(a);
        defer checkpoint.deinit();
        const raw = lua.raw_state.rootedValue(table.ref.index).table;
        const original = raw.array.items.ptr;
        failing.fail_index = failing.alloc_index + offset;
        const result = raw.set(lua.allocator(), .{ .integer = 1 }, .{ .integer = 9 });
        failing.fail_index = std.math.maxInt(usize);
        if (result) |_| {
            try lua.reset(&checkpoint);
            try std.testing.expectEqual(@as(i64, 7), raw.get(.{ .integer = 1 }).integer);
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(original, raw.array.items.ptr);
            try std.testing.expectEqual(@as(i64, 7), try table.get(1, i64));
            try std.testing.expectEqual(@as(usize, 0), lua.raw_state.rollback.?.dirty.items.len);
        }
    }
}

test "snapshot freezes borrowed input and memory file bytes on the source" {
    var input = [_]u8{ 'a', '\n' };
    var contents = [_]u8{ 'b', '\n' };
    var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .io = .{ .stdin = &input }, .filesystem = .{ .memory = &.{.{ .path = "data", .contents = &contents }} } } });
    defer lua.deinit();
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    input[0] = 'x';
    contents[0] = 'y';
    for (0..2) |_| {
        try lua.reset(&checkpoint);
        try lua.doString("assert(io.read('l')=='a'); local f=assert(io.open('data')); assert(f:read('l')=='b'); f:close()", .{});
    }
}

test "incremental module loads and native coroutine trampolines are reclaimed" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.addMemoryFile("fresh.lua", "return {value=42}");
    try lua.doString("co=coroutine.create(assert)", .{});
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    const sources = lua.raw_state.source_allocations.items.len;
    const protos = lua.raw_state.proto_allocations.items.len;
    for (0..3) |_| {
        try lua.doString("assert(require('fresh').value==42); assert(coroutine.resume(co,true))", .{});
        try lua.reset(&checkpoint);
        try std.testing.expectEqual(sources, lua.raw_state.source_allocations.items.len);
        try std.testing.expectEqual(protos, lua.raw_state.proto_allocations.items.len);
    }
}

test "scoped borrowed pointers are rejected and active scopes remain GC roots" {
    var copies: usize = 0;
    var finals: usize = 0;
    var disposals: usize = 0;
    var fail = false;
    var payload = ScopedPayload{ .copies = &copies, .finals = &finals, .disposals = &disposals, .fail = &fail };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try std.testing.expectError(error.ScopedAccessRequiresOwnedUserdata, lua.newUserdataPtr(ScopedPayload, &payload, .{ .snapshot = .{ .copy = ScopedPayload.copy, .dispose = ScopedPayload.dispose, .tracking = .scoped } }));
    var ud = try lua.newUserdata(ScopedPayload, payload, .{ .finalizer = ScopedPayload.finalize, .snapshot = .{ .copy = ScopedPayload.copy, .dispose = ScopedPayload.dispose, .tracking = .scoped } });
    const Context = struct { lua: *api.State, handle: *api.Userdata(ScopedPayload) };
    try ud.withRead(Context{ .lua = &lua, .handle = &ud }, struct {
        fn call(value: *const ScopedPayload, ctx: Context) !void {
            try std.testing.expectError(error.ScopedAccessConflict, ctx.handle.withMut(@as(i64, 1), ScopedPayload.mutate));
            ctx.handle.deinit();
            try ctx.lua.collect();
            try std.testing.expectEqual(@as(i64, 1), value.value);
            try std.testing.expectEqual(@as(usize, 0), value.finals.*);
        }
    }.call);
    try lua.collect();
    try std.testing.expectEqual(@as(usize, 1), finals);
}

test "incremental reset agrees with graph copy across weak GC and debug vararg writes" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.doString(
        \\collectgarbage('stop'); weak=setmetatable({}, {__mode='kv'})
        \\do local k={}; weak[k]={} end
        \\co=coroutine.create(function(...) local value=7; coroutine.yield(); return value,... end)
        \\assert(coroutine.resume(co,11,12))
    , .{});
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    const operations =
        \\assert(debug.setlocal(co,1,-1,99)); collectgarbage(); assert(next(weak)==nil)
        \\local ok, v, a, b=coroutine.resume(co); assert(ok); print(v,a,b)
    ;
    for (0..3) |_| {
        var copied = try checkpoint.clone(a);
        defer copied.deinit();
        try lua.doString(operations, .{});
        try copied.doString(operations, .{});
        try std.testing.expectEqualStrings(copied.raw_state.stdout.items, lua.raw_state.stdout.items);
        try lua.reset(&checkpoint);
        try std.testing.expectEqual(@as(usize, 0), lua.raw_state.stdout.items.len);
    }
}

test "journal clone first-write coroutine and GC allocation failures release all storage" {
    var source = try api.State.init(a, .{ .stdlib = .full });
    defer source.deinit();
    try source.doString(
        \\collectgarbage('stop'); t={1,2,3}; weak=setmetatable({}, {__mode='v'}); weak[1]={}
        \\co=coroutine.create(function(...) local saved={...}; coroutine.yield(); local f=function() return saved[1] end; t[1]=99; return f() end)
        \\assert(coroutine.resume(co,5))
    , .{});
    var checkpoint = try source.snapshot(a);
    defer checkpoint.deinit();
    try std.testing.checkAllAllocationFailures(a, struct {
        fn run(allocator: std.mem.Allocator, image: *const api.Snapshot) !void {
            var worker = try image.clone(allocator);
            defer worker.deinit();
            const co = worker.raw_state.getGlobal("co").thread;
            const result = try worker.raw_state.resumeCoroutine(co, &.{});
            switch (result) {
                .success => |values| worker.allocator().free(values),
                .failure => return error.UnexpectedCoroutineFailure,
            }
            try worker.raw_state.collectGarbageWithFinalizers(null);
            try worker.reset(image);
        }
    }.run, .{&checkpoint});
}

test "recapture retains error names when callback containers detach" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var callback = try lua.registerTyped("expected_bool", struct {
        fn call(_: bool) void {}
    }.call);
    defer callback.deinit();
    var first = try lua.snapshot(a);
    defer first.deinit();
    try std.testing.expectError(error.LuaError, callback.call(.{@as(i64, 1)}, void));
    var extra = try lua.registerTyped("another", struct {
        fn call() void {}
    }.call);
    defer extra.deinit();
    var second = try lua.snapshot(a);
    defer second.deinit();
    const message = try lua.errorMessage();
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "expected_bool") != null);
    try lua.reset(&second);
    const restored = try lua.errorMessage();
    defer lua.allocator().free(restored);
    try std.testing.expectEqualStrings(message, restored);
}

const concurrent_workers = 4;
const concurrent_iterations = 32;
const AtomicCount = std.atomic.Value(usize);

const ConcurrentCounters = struct {
    start: std.atomic.Value(bool) = .init(false),
    copies: AtomicCount = .init(0),
    disposals: AtomicCount = .init(0),
    finals: AtomicCount = .init(0),
    arrived: AtomicCount = .init(0),
    failed: AtomicCount = .init(0),
    image: ?*const @import("../runtime/state.zig").State = null,
};

const ConcurrentPayload = struct {
    counters: *ConcurrentCounters,
    value: usize = 17,

    fn finalize(self: *@This()) void {
        _ = self.counters.finals.fetchAdd(1, .monotonic);
    }

    fn copy(allocator: std.mem.Allocator, self: *const @This()) !*@This() {
        const counters = self.counters;
        if (counters.image) |image| {
            // Every hook invocation observes the pristine image, even while
            // other readers are inside their copy hooks. Live capture is guarded.
            try std.testing.expect(!image.snapshot_busy);
            const arrival = counters.arrived.fetchAdd(1, .acq_rel);
            if (arrival < concurrent_workers) {
                // Force the first clones to overlap. Failed clone attempts also
                // unblock the barrier, so a regression reports rather than hangs.
                while (counters.arrived.load(.acquire) + counters.failed.load(.acquire) < concurrent_workers)
                    std.atomic.spinLoopHint();
            }
        }
        const result = try allocator.create(@This());
        result.* = .{ .counters = counters, .value = self.value };
        _ = counters.copies.fetchAdd(1, .monotonic);
        return result;
    }

    fn dispose(allocator: std.mem.Allocator, self: *@This()) void {
        _ = self.counters.disposals.fetchAdd(1, .monotonic);
        allocator.destroy(self);
    }
};

const ConcurrentWorker = struct {
    checkpoint: api.Snapshot,
    counters: *ConcurrentCounters,
    shared: *ConcurrentPayload,
    wrapper_first: bool,
    failure: ?anyerror = null,

    fn run(self: *@This()) void {
        while (!self.counters.start.load(.acquire)) std.atomic.spinLoopHint();
        self.work() catch |err| {
            self.failure = err;
            _ = self.counters.failed.fetchAdd(1, .release);
        };
    }

    fn work(self: *@This()) !void {
        var owned = true;
        defer if (owned) self.checkpoint.deinit();
        for (0..concurrent_iterations) |iteration| {
            // Retain/release on the same backing also races other owners here.
            var local = self.checkpoint.retain();
            var local_owned = true;
            defer if (local_owned) local.deinit();
            var worker = try local.clone(a);
            defer worker.deinit();
            try worker.doString(
                \\assert(t.self == t and t.n == 7 and read() == 10)
                \\assert(require('m') == m and m.n == 23)
                \\assert(coroutine.status(co) == 'suspended')
                \\t.n = 99; bump(); m.n = 90
                \\local ok, n = coroutine.resume(co, 5); assert(ok and n == 15)
            , .{});
            try worker.reset(&local);
            try worker.doString(
                \\assert(t.self == t and t.n == 7 and read() == 10)
                \\assert(require('m') == m and m.n == 23)
                \\local ok, n = coroutine.resume(co, 2); assert(ok and n == 12)
            , .{});
            var shared = try worker.getGlobal("shared", api.Userdata(ConcurrentPayload));
            defer shared.deinit();
            try std.testing.expectEqual(self.shared, try shared.ptr());
            try std.testing.expectEqual(@as(usize, 17), (try shared.ptr()).value);
            try std.testing.expectEqual(@as(usize, 0), self.counters.finals.load(.acquire));
            if (iteration + 1 == concurrent_iterations and self.wrapper_first) {
                self.checkpoint.deinit();
                owned = false;
                local.deinit();
                local_owned = false;
            }
        }
        // Exercise the frozen-copy path when switching an unrelated live state.
        if (owned) {
            var other = try api.State.init(a, .{});
            defer other.deinit();
            try other.reset(&self.checkpoint);
            try other.doString("assert(t.n == 7 and read() == 10 and require('m').n == 23)", .{});
            self.checkpoint.deinit();
            owned = false;
        }
    }
};

test "retained snapshots concurrently clone reset and release immutable backing and userdata" {
    if (@import("builtin").single_threaded or @import("builtin").target.cpu.arch.isWasm()) return error.SkipZigTest;
    var counters: ConcurrentCounters = .{};
    var source = try api.State.init(a, .{ .stdlib = .full });
    var source_owned = true;
    defer if (source_owned) source.deinit();
    try source.addMemoryFile("m.lua", "return {n = 23}");
    try source.doString(
        \\t = {n = 7}; t.self = t; m = require('m')
        \\local n = 10; function read() return n end; function bump() n = n + 1 end
        \\co = coroutine.create(function() local x = coroutine.yield(); return 10 + x end)
        \\assert(coroutine.resume(co))
    , .{});
    var shared = try source.newUserdata(ConcurrentPayload, .{ .counters = &counters }, .{ .finalizer = ConcurrentPayload.finalize });
    const shared_ptr = try shared.ptr();
    try source.setGlobal("shared", shared);
    shared.deinit();
    var hooked = try source.newUserdata(ConcurrentPayload, .{ .counters = &counters }, .{ .snapshot = .{ .copy = ConcurrentPayload.copy, .dispose = ConcurrentPayload.dispose } });
    try source.setGlobal("hooked", hooked);
    hooked.deinit();
    // Both backing and hookless storage retain the source allocator. Its final
    // destruction must happen on a worker, after the source State is gone.
    var checkpoint = try source.snapshot(source.allocator());
    var checkpoint_owned = true;
    defer if (checkpoint_owned) checkpoint.deinit();
    counters.image = &checkpoint.backing.image.raw_state;
    var contexts: [concurrent_workers]ConcurrentWorker = undefined;
    for (&contexts, 0..) |*context, i| context.* = .{
        .checkpoint = checkpoint.retain(),
        .counters = &counters,
        .shared = shared_ptr,
        .wrapper_first = i % 2 == 0,
    };
    var threads: [concurrent_workers]std.Thread = undefined;
    var spawned: usize = 0;
    var joined = false;
    defer if (!joined) {
        // Also makes partial thread-spawn failure safe.
        for (contexts[spawned..]) |*context| context.checkpoint.deinit();
        _ = counters.failed.fetchAdd(concurrent_workers - spawned, .release);
        counters.start.store(true, .release);
        for (threads[0..spawned]) |thread| thread.join();
    };
    for (&threads, &contexts) |*thread, *context| {
        thread.* = try std.Thread.spawn(.{}, ConcurrentWorker.run, .{context});
        spawned += 1;
    }
    checkpoint.deinit();
    checkpoint_owned = false;
    source.deinit();
    source_owned = false;
    counters.start.store(true, .release);
    for (threads) |thread| thread.join();
    joined = true;
    for (contexts) |context| if (context.failure) |err| return err;
    try std.testing.expectEqual(@as(usize, 1), counters.finals.load(.acquire));
    const expected = 1 + 2 * concurrent_workers * concurrent_iterations + concurrent_workers / 2;
    try std.testing.expectEqual(@as(usize, expected), counters.copies.load(.acquire));
    try std.testing.expectEqual(counters.copies.load(.acquire), counters.disposals.load(.acquire));
}

test "simultaneous final hookless payload releases finalize dispose and destroy allocator once" {
    if (@import("builtin").single_threaded or @import("builtin").target.cpu.arch.isWasm()) return error.SkipZigTest;
    const types = @import("../runtime/types.zig");
    const Lifetime = struct {
        lifetime: types.AllocatorLifetime = .{ .destroy = destroy },
        destroyed: *AtomicCount,
        fn destroy(lifetime: *types.AllocatorLifetime) void {
            const self: *@This() = @fieldParentPtr("lifetime", lifetime);
            _ = self.destroyed.fetchAdd(1, .monotonic);
            a.destroy(self);
        }
    };
    const Worker = struct {
        fn finalize(ptr: *anyopaque, _: ?*const anyopaque) void {
            ConcurrentPayload.finalize(@ptrCast(@alignCast(ptr)));
        }
        fn dispose(allocator: std.mem.Allocator, ptr: *anyopaque) void {
            ConcurrentPayload.dispose(allocator, @ptrCast(@alignCast(ptr)));
        }
        fn run(payload: *types.UserdataPayload, gate: *std.atomic.Value(bool)) void {
            while (!gate.load(.acquire)) std.atomic.spinLoopHint();
            payload.release(false);
        }
    };
    var counters: ConcurrentCounters = .{};
    var destroyed: AtomicCount = .init(0);
    for (0..64) |_| {
        var gate: std.atomic.Value(bool) = .init(false);
        const lifetime = try a.create(Lifetime);
        lifetime.* = .{ .destroyed = &destroyed };
        const value = try a.create(ConcurrentPayload);
        value.* = .{ .counters = &counters };
        const payload = try a.create(types.UserdataPayload);
        payload.* = .{
            .allocator = a,
            .lifetime = &lifetime.lifetime,
            .ptr = value,
            .finalizer = Worker.finalize,
            .finalizer_data = null,
            .dispose = Worker.dispose,
        };
        var threads: [concurrent_workers]std.Thread = undefined;
        var spawned: usize = 0;
        defer {
            gate.store(true, .release);
            for (threads[0..spawned]) |thread| thread.join();
        }
        // Transfer a reference to each thread, then release the initial owner.
        for (&threads) |*thread| {
            payload.retain();
            thread.* = std.Thread.spawn(.{}, Worker.run, .{ payload, &gate }) catch |err| {
                payload.release(false);
                payload.release(false);
                return err;
            };
            spawned += 1;
        }
        payload.release(false);
        gate.store(true, .release);
        for (threads) |thread| thread.join();
        spawned = 0;
    }
    try std.testing.expectEqual(@as(usize, 64), counters.finals.load(.acquire));
    try std.testing.expectEqual(@as(usize, 64), counters.disposals.load(.acquire));
    try std.testing.expectEqual(@as(usize, 64), destroyed.load(.acquire));
}
