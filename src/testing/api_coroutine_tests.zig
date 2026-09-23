const std = @import("std");
const api = @import("../root.zig");
const a = std.testing.allocator;

fn ask(ctx: *api.Context) !void {
    try std.testing.expect(ctx.isYieldable());
    var current = try ctx.coroutine();
    defer current.deinit();
    try std.testing.expectEqual(api.CoroutineStatus.running, try current.status());
    try std.testing.expectEqual(ctx.coroutineIdentity(), try current.identity());
    return ctx.yield(.{@as(i64, 10)});
}

test "thread lifecycle converts only active branches and preserves resume arguments" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var chunk = try lua.loadString(
        \\local first = ...
        \\started = true
        \\local answer, absent = coroutine.yield(first, nil)
        \\assert(absent == nil)
        \\coroutine.yield(answer, nil)
        \\return 'finished'
    , .{});
    defer chunk.deinit();
    var thread = try lua.newCoroutine(chunk);
    defer thread.deinit();
    try std.testing.expectEqual(api.CoroutineStatus.suspended, try thread.status());
    try std.testing.expectEqual(null, try lua.getGlobal("started", ?bool));
    const Yield = api.Tuple(&.{ i64, ?i64 });
    var first = try thread.resumeCoroutine(.{41}, Yield, []const u8);
    defer first.deinit();
    try std.testing.expectEqual(41, first.yielded.get(0));
    try std.testing.expectEqual(null, first.yielded.get(1));
    var second = try thread.resumeCoroutine(.{42}, Yield, []const u8);
    defer second.deinit();
    try std.testing.expectEqual(42, second.yielded.get(0));
    var last = try thread.resumeCoroutine(.{}, Yield, []const u8);
    defer last.deinit();
    try std.testing.expectEqualStrings("finished", last.returned);
    try std.testing.expectEqual(api.CoroutineStatus.dead, try thread.status());
    try std.testing.expectError(error.LuaError, thread.resumeCoroutine(.{}, void, void));
    try thread.close();

    var dialogue = try lua.loadString("coroutine.yield('dialogue')", .{});
    defer dialogue.deinit();
    var story = try lua.newCoroutine(dialogue);
    defer story.deinit();
    var line = try story.resumeCoroutine(.{}, []const u8, void);
    defer line.deinit();
    try std.testing.expectEqualStrings("dialogue", line.yielded);
    var done = try story.resumeCoroutine(.{}, []const u8, void);
    defer done.deinit();
    try std.testing.expect(done == .returned);
}

test "thread handles round trip through globals tables dynamic values tuples and callbacks" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("co = coroutine.create(function(t) coroutine.yield(t); return t end)", .{});
    var thread = try lua.getGlobal("co", api.Coroutine);
    defer thread.deinit();
    var value = try lua.push(thread);
    defer value.deinit();
    try std.testing.expectEqual(try thread.identity(), try value.coroutine.identity());
    var read = try lua.read(value, api.Coroutine);
    defer read.deinit();
    var table = try lua.createTable(.{});
    defer table.deinit();
    try table.set(thread, value);
    var stored = try table.get(thread, api.Coroutine);
    defer stored.deinit();
    try std.testing.expectEqual(try thread.identity(), try stored.identity());
    var echo = try lua.registerTyped("echo", struct {
        fn call(t: api.Coroutine) api.Coroutine {
            return t;
        }
    }.call);
    defer echo.deinit();
    var echoed = try echo.call(.{thread}, api.Coroutine);
    defer echoed.deinit();
    try std.testing.expectEqual(try thread.identity(), try echoed.identity());
    const Threads = api.Tuple(&.{ api.Coroutine, ?api.Coroutine });
    var first = try thread.resumeCoroutine(.{thread}, Threads, api.Coroutine);
    defer first.deinit();
    try std.testing.expectEqual(try thread.identity(), try first.yielded.get(0).identity());
    try std.testing.expectEqual(null, first.yielded.get(1));
    var last = try thread.resumeCoroutine(.{}, Threads, api.Coroutine);
    defer last.deinit();
    try std.testing.expectEqual(try thread.identity(), try last.returned.identity());
    var other = try api.State.init(a, .{});
    defer other.deinit();
    try std.testing.expectError(error.InvalidHandle, other.setGlobal("thread", value));
    try std.testing.expectError(error.InvalidHandle, other.newCoroutine(echo));
}

test "callback current thread survives host retirement and rejects main lifecycle operations" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var callback = try lua.register("current", struct {
        fn call(ctx: *api.Context) !void {
            try std.testing.expect(!ctx.isYieldable());
            var thread = try ctx.coroutine();
            defer thread.deinit();
            try ctx.returnValues(thread);
        }
    }.call);
    defer callback.deinit();
    var retained = try callback.call(.{}, api.Coroutine);
    defer retained.deinit();
    const identity = try retained.identity();
    try lua.collect();
    try std.testing.expectEqual(identity, try retained.identity());
    try std.testing.expectEqual(api.CoroutineStatus.dead, try retained.status());
    try std.testing.expectError(error.LuaError, retained.close());
    try std.testing.expectError(error.LuaError, retained.resumeCoroutine(.{}, void, void));
}

test "plain typed and entry callbacks yield after defers without reentering Zig" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var plain = try lua.register("ask", ask);
    defer plain.deinit();
    try lua.setGlobal("ask", plain);
    var typed = try lua.registerTyped("typed", struct {
        fn call(ctx: *api.Context, prompt: []const u8) !i64 {
            defer ctx.state().raw_state.putGlobal("cleaned", .{ .boolean = true }) catch unreachable;
            return ctx.yield(.{prompt});
        }
    }.call);
    defer typed.deinit();
    try lua.setGlobal("typed", typed);
    var chunk = try lua.loadString("local n = ask(); local answer = typed('prompt'); return n + answer", .{});
    defer chunk.deinit();
    var thread = try lua.newCoroutine(chunk);
    defer thread.deinit();
    var first = try thread.resumeCoroutine(.{}, i64, i64);
    defer first.deinit();
    try std.testing.expectEqual(10, first.yielded);
    var second = try thread.resumeCoroutine(.{20}, []const u8, i64);
    defer second.deinit();
    try std.testing.expectEqualStrings("prompt", second.yielded);
    try std.testing.expect(try lua.getGlobal("cleaned", bool));
    var last = try thread.resumeCoroutine(.{22}, void, i64);
    defer last.deinit();
    try std.testing.expectEqual(42, last.returned);
    var entry = try lua.newCoroutine(plain);
    defer entry.deinit();
    var entry_first = try entry.resumeCoroutine(.{}, i64, i64);
    defer entry_first.deinit();
    try std.testing.expectEqual(10, entry_first.yielded);
    var entry_last = try entry.resumeCoroutine(.{42}, void, i64);
    defer entry_last.deinit();
    try std.testing.expectEqual(42, entry_last.returned);
}

test "host yield preserves Lua protected iterator metamethod tail and scope close continuations" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    var callback = try lua.register("ask", ask);
    defer callback.deinit();
    try lua.setGlobal("ask", callback);
    const sources = [_][]const u8{
        "return ask()",
        "local function nested() return ask() end; return nested()",
        "local ok, n = pcall(ask); assert(ok); return n",
        "local ok, n = xpcall(function() error('failure') end, ask); assert(not ok); return n",
        "for n in function() return ask() end do return n end",
        "local t = setmetatable({}, {__index=ask}); return t.missing",
        "local t = setmetatable({}, {__add=ask}); return t + t",
        "local t = setmetatable({}, {__len=ask}); return #t",
        "local t = setmetatable({}, {__pairs=function() local n=ask(); return next, {n}, nil end}); for _, n in pairs(t) do return n end",
        "local t = setmetatable({}, {__pairs=ask}); return pairs(t)",
        "local n; do local guard <close> = setmetatable({}, {__close=function() n=ask() end}) end; return n",
        "local ok, err = pcall(function() local guard <close> = setmetatable({}, {__close=ask}); error(42) end); assert(not ok); return err",
    };
    for (sources) |source| {
        var chunk = try lua.loadString(source, .{});
        defer chunk.deinit();
        var thread = try lua.newCoroutine(chunk);
        defer thread.deinit();
        var first = thread.resumeCoroutine(.{}, i64, i64) catch |err| {
            std.debug.print("yield source: {s}\n", .{source});
            return err;
        };
        defer first.deinit();
        try std.testing.expectEqual(10, first.yielded);
        try lua.collect();
        var last = try thread.resumeCoroutine(.{42}, void, i64);
        defer last.deinit();
        try std.testing.expectEqual(42, last.returned);
    }
}

fn uncheckedYield(ctx: *api.Context) !void {
    try std.testing.expect(!ctx.isYieldable());
    var current = try ctx.coroutine();
    defer current.deinit();
    try std.testing.expectError(error.LuaError, current.close());
    return ctx.yield(.{42});
}

test "non yielding host native close and finalizer boundaries reject callback yields" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var callback = try lua.register("ask", uncheckedYield);
    defer callback.deinit();
    try lua.setGlobal("ask", callback);
    try std.testing.expectError(error.LuaError, callback.call(.{}, void));
    try std.testing.expectError(error.LuaError, lua.doString("ask()", .{}));
    var call = try lua.register("call_sync", struct {
        fn run(ctx: *api.Context) !void {
            var function = try ctx.arg(0, api.Function);
            defer function.deinit();
            try ctx.callNonYielding(function, .{}, void);
        }
    }.run);
    defer call.deinit();
    try lua.setGlobal("call_sync", call);
    var chunk = try lua.loadString(
        \\local ok, err = pcall(call_sync, ask)
        \\assert(not ok and err:find('yield'))
        \\local t = setmetatable({}, {__index=ask})
        \\ok, err = pcall(function() for _ in ipairs(t) do end end)
        \\assert(not ok and err:find('yield'))
        \\return 42
    , .{});
    defer chunk.deinit();
    var thread = try lua.newCoroutine(chunk);
    defer thread.deinit();
    var result = try thread.resumeCoroutine(.{}, void, i64);
    defer result.deinit();
    try std.testing.expectEqual(42, result.returned);
    var closing = try lua.loadString("local guard <close> = setmetatable({}, {__close=ask}); coroutine.yield()", .{});
    defer closing.deinit();
    var close_thread = try lua.newCoroutine(closing);
    defer close_thread.deinit();
    var yielded = try close_thread.resumeCoroutine(.{}, void, void);
    defer yielded.deinit();
    try std.testing.expectError(error.LuaError, close_thread.close());
    try std.testing.expectEqual(api.CoroutineStatus.dead, try close_thread.status());
    try lua.doString("setmetatable({}, {__gc=function() local ok, err=pcall(ask); assert(not ok and err:find('yield')); finalized=true end})", .{});
    try lua.collect();
    try std.testing.expect(try lua.getGlobal("finalized", bool));
}

test "coroutine close retains arbitrary errors and deinit only releases its root" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("marker={}; co=coroutine.create(function() error(marker) end)", .{});
    var thread = try lua.getGlobal("co", api.Coroutine);
    defer thread.deinit();
    var result = try thread.protectedResume(.{}, void, void);
    try std.testing.expect(result == .lua_error);
    defer result.lua_error.deinit();
    var value = try result.lua_error.value();
    defer value.deinit();
    var marker = try lua.getGlobal("marker", api.Table);
    defer marker.deinit();
    try std.testing.expectEqual(try marker.identity(), try value.table.identity());
    try std.testing.expectError(error.LuaError, thread.close());
    var captured = lua.takeErrorValue().?;
    defer captured.deinit();
    var captured_value = try captured.value();
    defer captured_value.deinit();
    try std.testing.expectEqual(try marker.identity(), try captured_value.table.identity());
    try lua.doString("co=coroutine.create(function() local guard <close> = setmetatable({}, {__close=function() closed=true; error(marker) end}); coroutine.yield() end)", .{});
    var pending = try lua.getGlobal("co", api.Coroutine);
    var first = try pending.resumeCoroutine(.{}, void, void);
    first.deinit();
    pending.deinit();
    try std.testing.expectEqual(null, try lua.getGlobal("closed", ?bool));
    pending = try lua.getGlobal("co", api.Coroutine);
    defer pending.deinit();
    var close_result = try pending.protectedClose();
    try std.testing.expect(close_result == .lua_error);
    defer close_result.lua_error.deinit();
    var close_value = try close_result.lua_error.value();
    defer close_value.deinit();
    try lua.collect();
    try std.testing.expectEqual(try marker.identity(), try close_value.table.identity());
    try std.testing.expect(try lua.getGlobal("closed", bool));
    try std.testing.expectEqual(api.CoroutineStatus.dead, try pending.status());
    try std.testing.expect((try pending.protectedClose()) == .ok);
    try pending.close();
}

test "conversion failures advance thread and release partial tuple handles" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var chunk = try lua.loadString("coroutine.yield({}, {}, 'bad'); return {}, nil", .{});
    defer chunk.deinit();
    var thread = try lua.newCoroutine(chunk);
    defer thread.deinit();
    const roots = lua.raw_state.activeRootCount();
    try std.testing.expectError(error.TypeMismatch, thread.resumeCoroutine(.{}, api.Tuple(&.{ api.Table, ?api.Table, i64 }), void));
    try std.testing.expectEqual(roots, lua.raw_state.activeRootCount());
    try std.testing.expectEqual(api.CoroutineStatus.suspended, try thread.status());
    var result = try thread.resumeCoroutine(.{}, void, api.Tuple(&.{ api.Table, ?api.Table }));
    try lua.collect();
    try result.returned.get(0).set("retained", true);
    result.deinit();
    try std.testing.expectEqual(roots, lua.raw_state.activeRootCount());
    try std.testing.expectEqual(api.CoroutineStatus.dead, try thread.status());
}

test "suspended host yield values survive GC snapshots independent resumes and reset" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var callback = try lua.register("ask", struct {
        fn run(ctx: *api.Context) !void {
            var table = try ctx.state().createTable(.{});
            defer table.deinit();
            try table.set("value", 42);
            return ctx.yield(.{table});
        }
    }.run);
    defer callback.deinit();
    try lua.setGlobal("ask", callback);
    var chunk = try lua.loadString("local answer=ask(); return answer + 1", .{});
    defer chunk.deinit();
    var thread = try lua.newCoroutine(chunk);
    defer thread.deinit();
    try lua.setGlobal("co", thread);
    lua.raw_state.collect_after_instruction = true;
    var first = try thread.resumeCoroutine(.{}, api.Table, i64);
    defer first.deinit();
    try lua.collect();
    try std.testing.expectEqual(42, try first.yielded.get("value", i64));
    var snapshot = try lua.snapshot(a);
    defer snapshot.deinit();
    for (0..2) |i| {
        var worker = try snapshot.newState(a);
        defer worker.deinit();
        var co = try worker.getGlobal("co", api.Coroutine);
        defer co.deinit();
        var returned = try co.resumeCoroutine(.{i}, void, i64);
        defer returned.deinit();
        try std.testing.expectEqual(@as(i64, @intCast(i + 1)), returned.returned);
        try worker.reset();
        try std.testing.expectError(error.InvalidHandle, co.status());
        try std.testing.expectError(error.InvalidHandle, co.close());
        try std.testing.expectError(error.InvalidHandle, co.resumeCoroutine(.{}, void, void));
        var reset = try worker.getGlobal("co", api.Coroutine);
        defer reset.deinit();
        try reset.close();
    }
    try std.testing.expectEqual(api.CoroutineStatus.suspended, try thread.status());
    var last = try thread.resumeCoroutine(.{41}, void, i64);
    defer last.deinit();
    try std.testing.expectEqual(42, last.returned);
    try lua.collect();
    try std.testing.expectEqual(42, try first.yielded.get("value", i64));
}

test "running and normal threads reject host lifecycle changes while Lua self close still works" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var check = try lua.register("check", struct {
        fn call(ctx: *api.Context) !void {
            var current = try ctx.coroutine();
            defer current.deinit();
            try std.testing.expectError(error.LuaError, current.close());
            try std.testing.expectError(error.LuaError, current.resumeCoroutine(.{}, void, void));
            var parent = try ctx.arg(0, api.Coroutine);
            defer parent.deinit();
            try std.testing.expectEqual(api.CoroutineStatus.normal, try parent.status());
            try std.testing.expectError(error.LuaError, parent.close());
            try std.testing.expectError(error.LuaError, parent.resumeCoroutine(.{}, void, void));
            try std.testing.expectEqual(api.CoroutineStatus.running, try current.status());
            return ctx.yield(.{});
        }
    }.call);
    defer check.deinit();
    try lua.setGlobal("check", check);
    try lua.doString(
        \\local parent = coroutine.running()
        \\local co = coroutine.create(function() check(parent); coroutine.close(); error('unreachable') end)
        \\assert(coroutine.resume(co))
        \\assert(coroutine.status(co) == 'suspended')
        \\assert(coroutine.resume(co))
        \\assert(coroutine.status(co) == 'dead')
    , .{});
}

test "userdata method scopes finish before host yield and rejected conversion never suspends" {
    const Payload = struct {
        value: i64 = 0,
        pub fn ask(self: *@This(), ctx: *api.Context) !void {
            self.value += 1;
            return ctx.yield(.{self.value});
        }
        fn copy(allocator: std.mem.Allocator, self: *const @This()) !*@This() {
            const result = try allocator.create(@This());
            result.* = self.*;
            return result;
        }
        fn dispose(allocator: std.mem.Allocator, self: *@This()) void {
            allocator.destroy(self);
        }
        fn read(self: *const @This(), _: void) i64 {
            return self.value;
        }
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var payload = try lua.newUserdataAuto(Payload, .{}, .{ .snapshot = .{ .copy = Payload.copy, .dispose = Payload.dispose, .tracking = .scoped } });
    defer payload.deinit();
    try lua.setGlobal("payload", payload);
    var chunk = try lua.loadString("return payload:ask()", .{});
    defer chunk.deinit();
    var thread = try lua.newCoroutine(chunk);
    defer thread.deinit();
    try lua.setGlobal("co", thread);
    var first = try thread.resumeCoroutine(.{}, i64, i64);
    defer first.deinit();
    try std.testing.expectEqual(1, first.yielded);
    try std.testing.expect(lua.raw_state.userdata_scope == null);
    try std.testing.expectEqual(1, try payload.withRead({}, Payload.read));
    var snapshot = try lua.snapshot(a);
    defer snapshot.deinit();
    var last = try thread.resumeCoroutine(.{42}, void, i64);
    defer last.deinit();
    try std.testing.expectEqual(42, last.returned);

    var bad = try lua.register("bad", struct {
        fn call(ctx: *api.Context) !void {
            return ctx.yield(.{ 1, @as(u128, std.math.maxInt(u128)) });
        }
    }.call);
    defer bad.deinit();
    try lua.setGlobal("bad", bad);
    var bad_chunk = try lua.loadString("local ok, err=pcall(bad); assert(not ok and err:find('integer')); return 42", .{});
    defer bad_chunk.deinit();
    var bad_thread = try lua.newCoroutine(bad_chunk);
    defer bad_thread.deinit();
    var result = try bad_thread.resumeCoroutine(.{}, void, i64);
    defer result.deinit();
    try std.testing.expectEqual(42, result.returned);
}

test "thread startup stack limits and cumulative instruction failures become Lua errors" {
    var lua = try api.State.init(a, .{ .limits = .{ .max_stack_values = 2 } });
    defer lua.deinit();
    var chunk = try lua.loadString("return 1,2,3,4,5", .{});
    defer chunk.deinit();
    var thread = try lua.newCoroutine(chunk);
    defer thread.deinit();
    var failure = try thread.protectedResume(.{}, void, void);
    try std.testing.expect(failure == .lua_error);
    defer failure.lua_error.deinit();
    try std.testing.expectEqual(api.CoroutineStatus.dead, try thread.status());
    const message = try failure.lua_error.message();
    defer a.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "stack overflow") != null);
    try std.testing.expectError(error.LuaError, thread.close());

    var budgeted = try api.State.init(a, .{ .limits = .{ .max_instructions = 30 } });
    defer budgeted.deinit();
    var loop = try budgeted.loadString("while true do coroutine.yield(1) end", .{});
    defer loop.deinit();
    var worker = try budgeted.newCoroutine(loop);
    defer worker.deinit();
    var count: usize = 0;
    while (worker.resumeCoroutine(.{}, i64, void)) |result| {
        var owned = result;
        owned.deinit();
        count += 1;
        try std.testing.expect(count < 30);
    } else |err| try std.testing.expectEqual(error.LuaError, err);
    try std.testing.expect(count > 1);
    try std.testing.expectEqual(api.CoroutineStatus.dead, try worker.status());
}

test "allocation failures during thread creation resume and suspension leave valid lifecycle state" {
    // Fail each allocation after setup, including callback staging, suspension,
    // result copying and roots; a successful pass bounds the sweep.
    var offset: usize = 0;
    while (offset < 200) : (offset += 1) {
        var failing = std.testing.FailingAllocator.init(a, .{});
        var lua = try api.State.init(failing.allocator(), .{});
        defer lua.deinit();
        var callback = try lua.register("ask", struct {
            fn call(ctx: *api.Context) !void {
                var table = try ctx.state().createTable(.{});
                defer table.deinit();
                return ctx.yield(.{ table, 1, 2, 3, 4, 5 });
            }
        }.call);
        defer callback.deinit();
        failing.fail_index = failing.alloc_index + offset;
        const run = struct {
            fn call(state: *api.State, entry: api.Function) !void {
                var thread = try state.newCoroutine(entry);
                defer thread.deinit();
                var first = thread.resumeCoroutine(.{}, api.Table, api.Table) catch |err| {
                    const status = try thread.status();
                    try std.testing.expect(status == .dead or status == .suspended);
                    return err;
                };
                defer first.deinit();
                try std.testing.expect(first == .yielded);
                var last = try thread.resumeCoroutine(.{first.yielded}, void, api.Table);
                defer last.deinit();
                try std.testing.expectEqual(api.CoroutineStatus.dead, try thread.status());
            }
        }.call;
        run(&lua, callback) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
        };
        if (!failing.has_induced_failure) break;
    }
    try std.testing.expect(offset < 200);
}

test "callback yield memory limit errors are protected Lua failures without suspension" {
    var lua = try api.State.init(a, .{ .stdlib = .base, .limits = .{ .max_memory = 128 * 1024 } });
    defer lua.deinit();
    var callback = try lua.register("large", struct {
        const payload = [_]u8{'x'} ** (512 * 1024);
        fn call(ctx: *api.Context) !void {
            return ctx.yield(.{payload[0..]});
        }
    }.call);
    defer callback.deinit();
    var thread = try lua.newCoroutine(callback);
    defer thread.deinit();
    var result = try thread.protectedResume(.{}, void, void);
    try std.testing.expect(result == .lua_error);
    defer result.lua_error.deinit();
    const message = try result.lua_error.message();
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "memory limit") != null);
    try std.testing.expectEqual(api.CoroutineStatus.dead, try thread.status());
}

test "interleaved host yields survive repeated collection without leaking roots" {
    const thread_count = 16;
    const rounds = 64;
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var ask_fn = try lua.register("ask", struct {
        fn call(ctx: *api.Context) !void {
            var table = try ctx.state().createTable(.{});
            defer table.deinit();
            const id = try ctx.arg(0, i64);
            const step = try ctx.arg(1, i64);
            try table.set("id", id);
            try table.set("step", step);
            return ctx.yield(.{table});
        }
    }.call);
    defer ask_fn.deinit();
    try lua.setGlobal("ask", ask_fn);
    var chunk = try lua.loadString(
        \\local id = ...
        \\for step = 1, 64 do
        \\    assert(ask(id, step) == id * 1000 + step)
        \\end
        \\return id
    , .{});
    defer chunk.deinit();

    var threads: [thread_count]api.Coroutine = undefined;
    var created: usize = 0;
    defer for (threads[0..created]) |*thread| thread.deinit();
    for (&threads) |*thread| {
        thread.* = try lua.newCoroutine(chunk);
        created += 1;
        try std.testing.expectEqual(api.CoroutineStatus.suspended, try thread.status());
    }
    const roots = lua.raw_state.activeRootCount();
    for (0..rounds) |round| {
        for (0..thread_count) |offset| {
            const id = (offset + round) % thread_count;
            const step: i64 = @intCast(round + 1);
            var result = if (round == 0)
                try threads[id].resumeCoroutine(.{@as(i64, @intCast(id))}, api.Table, i64)
            else
                try threads[id].resumeCoroutine(.{@as(i64, @intCast(id)) * 1000 + @as(i64, @intCast(round))}, api.Table, i64);
            defer result.deinit();
            try std.testing.expect(result == .yielded);
            try std.testing.expectEqual(@as(i64, @intCast(id)), try result.yielded.get("id", i64));
            try std.testing.expectEqual(step, try result.yielded.get("step", i64));
        }
        if (round % 8 == 0) try lua.collect();
        try std.testing.expectEqual(roots, lua.raw_state.activeRootCount());
    }
    for (&threads, 0..) |*thread, id| {
        var result = try thread.resumeCoroutine(.{@as(i64, @intCast(id)) * 1000 + @as(i64, rounds)}, void, i64);
        defer result.deinit();
        try std.testing.expect(result == .returned);
        try std.testing.expectEqual(@as(i64, @intCast(id)), result.returned);
        try std.testing.expectEqual(api.CoroutineStatus.dead, try thread.status());
        try thread.close();
    }
    try lua.collect();
    try std.testing.expectEqual(roots, lua.raw_state.activeRootCount());
}
