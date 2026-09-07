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
    try std.testing.expectEqual(@as(usize, 2), disposals);
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
    var checkpoint = try lua.snapshot(a);
    defer checkpoint.deinit();
    checkpoint.image.raw_state.options.max_memory = 1;
    try std.testing.expectError(error.OutOfMemory, lua.reset(&checkpoint));
    try std.testing.expectEqualStrings("owned", try chunk.call(.{}, []const u8));
    checkpoint.image.raw_state.options.max_memory = 4 * 1024 * 1024;
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
