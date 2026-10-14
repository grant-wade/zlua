const std = @import("std");
const api = @import("../api.zig");
const runtime = @import("../runtime.zig");
const a = std.testing.allocator;

test "host callback small results are allocation free and spill failure preserves inline roots" {
    const Returns = @import("../runtime/types.zig").CallbackReturns;
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    var values: Returns = .{};
    defer values.deinit(failing.allocator());
    for (0..4) |i| try values.append(failing.allocator(), .{ .integer = @intCast(i) });
    try std.testing.expectEqual(0, failing.alloc_index);
    try std.testing.expectError(error.OutOfMemory, values.append(failing.allocator(), .nil));
    try std.testing.expectEqual(4, values.items().len);
    values.clearRetainingCapacity();
    try values.append(failing.allocator(), .{ .integer = 7 });
    try std.testing.expectEqual(7, values.items()[0].integer);
    var spill: Returns = .{};
    defer spill.deinit(a);
    for (0..8) |i| try spill.append(a, .{ .integer = @intCast(i) });
    for (spill.items(), 0..) |v, i| try std.testing.expectEqual(@as(i64, @intCast(i)), v.integer);
    spill.clearRetainingCapacity();
    try spill.append(a, .{ .integer = 9 });
    try std.testing.expectEqual(1, spill.items().len);
}

test "shared userdata metatables equality raw table traversal and host type checking" {
    const Payload = struct { id: i64 };
    const Host = struct {
        fn eq(ctx: *api.Context) !void {
            var lhs = try ctx.arg(0, api.Userdata(Payload));
            defer lhs.deinit();
            var rhs = try ctx.arg(1, api.Userdata(Payload));
            defer rhs.deinit();
            try ctx.returnValues((try lhs.ptr()).id == (try rhs.ptr()).id);
        }
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var meta = try lua.createTable(.{});
    defer meta.deinit();
    var eq = try lua.register("equal", Host.eq);
    defer eq.deinit();
    try meta.set("__eq", eq);
    try lua.setGlobal("host_eq", eq);
    try meta.set("__metatable", "private");
    const tables = lua.raw_state.table_allocations.items.len;
    var x = try lua.newUserdata(Payload, .{ .id = 1 }, .{ .metatable = meta });
    defer x.deinit();
    var y = try lua.newUserdata(Payload, .{ .id = 1 }, .{ .metatable = meta });
    defer y.deinit();
    var z = try lua.newUserdata(Payload, .{ .id = 2 }, .{ .metatable = meta });
    defer z.deinit();
    try std.testing.expectEqual(tables, lua.raw_state.table_allocations.items.len);
    try lua.setGlobal("x", x);
    try lua.setGlobal("y", y);
    try lua.setGlobal("z", z);
    try std.testing.expect(lua.raw_state.rootedValue(x.ref.index).userdata.metatable == lua.raw_state.rootedValue(meta.ref.index).table);
    try runLua(&lua,
        \\assert(getmetatable(x) == 'private', 'meta before'); assert(host_eq(x,y), 'direct eq'); assert(x == y, 'eq'); assert(x ~= z, 'ne'); assert(not rawequal(x, y), 'raw')
        \\local equal = x == y; assert(equal)
        \\if x ~= y then error('branch equality') end
        \\assert(getmetatable(x) == 'private')
        \\assert(x ~= {} and x ~= 1 and x ~= nil)
        \\data = setmetatable({[1]='one', [7]='seven', name='test'}, {__index=function() error('index') end, __pairs=function() error('pairs') end, __metatable='hidden'})
    );
    var data = try lua.getGlobal("data", api.Table);
    defer data.deinit();
    var alias = try lua.getGlobal("data", api.Table);
    defer alias.deinit();
    try std.testing.expectEqual(try data.identity(), try alias.identity());
    var actual_meta = (try data.getMetatable()).?;
    defer actual_meta.deinit();
    try std.testing.expectEqualStrings("hidden", try actual_meta.get("__metatable", []const u8));
    try std.testing.expect((try data.rawGet("absent", ?bool)) == null);
    var key: api.Value = .nil;
    defer key.deinit();
    var count: usize = 0;
    while (try data.rawNext(key)) |entry_value| {
        var entry = entry_value;
        key.deinit();
        key = entry.key;
        defer entry.value.deinit();
        count += 1;
    }
    try std.testing.expectEqual(3, count);
    var any = try lua.getGlobal("x", api.AnyUserdata);
    defer any.deinit();
    var typed = try any.as(Payload);
    defer typed.deinit();
    try std.testing.expectEqual(1, (try typed.ptr()).id);
    try std.testing.expectError(error.TypeMismatch, any.as(struct { other: bool }));
    var foreign = try api.State.init(a, .{});
    defer foreign.deinit();
    try std.testing.expectError(error.InvalidHandle, foreign.newUserdata(Payload, .{ .id = 1 }, .{ .metatable = meta }));
}

test "inline and spilled callback results remain rooted across GC and nested callbacks" {
    const Host = struct {
        fn results(ctx: *api.Context) !void {
            const count = try ctx.arg(0, usize);
            for (0..count) |i| {
                var table = try ctx.state().createTable(.{});
                try table.set("n", i);
                try ctx.pushReturn(table);
                table.deinit();
                if (ctx.state().raw_state.stress_step) {
                    _ = try ctx.state().stepGc(.{});
                } else try ctx.state().collect();
            }
            var callback = try ctx.arg(1, api.Function);
            defer callback.deinit();
            try ctx.callNonYielding(callback, .{}, void);
            if (ctx.state().raw_state.stress_step) {
                _ = try ctx.state().stepGc(.{});
            } else try ctx.state().collect();
        }
    };
    for ([_]bool{ false, true }) |tiny_steps| {
        var lua = try api.State.init(a, .{});
        defer lua.deinit();
        lua.raw_state.stress_step = tiny_steps;
        if (tiny_steps) {
            _ = lua.setGcMode(.incremental);
            _ = try lua.setGcParam(.stepsize, 8);
            _ = try lua.setGcParam(.stepmul, 100);
        }
        var function = try lua.register("results", Host.results);
        defer function.deinit();
        try lua.setGlobal("results", function);
        try runLua(&lua,
            \\for _, n in ipairs({0,1,4,5,8}) do
            \\ local r = table.pack(results(n, function()
            \\   local inner = table.pack(results(4, function() collectgarbage() end))
            \\   assert(inner.n == 4 and inner[4].n == 3)
            \\ end))
            \\ assert(r.n == n)
            \\ for i=1,n do assert(r[i].n == i-1) end
            \\end
        );
    }
}

test "non-yielding callback stays on the current thread and unwinds before returning errors" {
    const Host = struct {
        fn call(ctx: *api.Context) !void {
            const thread = ctx.coroutineIdentity();
            var callback = try ctx.arg(0, api.Function);
            defer callback.deinit();
            ctx.callNonYielding(callback, .{}, void) catch |err| {
                // __close has run before the host can release its lock.
                try std.testing.expect(try ctx.state().getGlobal("closed", bool));
                try std.testing.expectEqual(thread, ctx.coroutineIdentity());
                return err;
            };
        }
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var function = try lua.register("host_call", Host.call);
    defer function.deinit();
    try lua.setGlobal("host_call", function);
    try runLua(&lua,
        \\local marker = {}
        \\local co = coroutine.create(function()
        \\ local me = coroutine.running()
        \\ closed = false
        \\ local ok, err = pcall(host_call, function()
        \\   assert(coroutine.running() == me)
        \\   local guard <close> = setmetatable({}, {__close=function() closed=true end})
        \\   error(marker)
        \\ end)
        \\ assert(not ok and err == marker and closed)
        \\ closed = false
        \\ ok, err = pcall(host_call, function()
        \\   local guard <close> = setmetatable({}, {__close=function() closed=true end})
        \\   coroutine.yield()
        \\ end)
        \\ assert(not ok and tostring(err):find('yield') and closed)
        \\ host_call(function() assert(coroutine.running() == me) end)
        \\end)
        \\local ok, err = coroutine.resume(co); assert(ok, tostring(err))
        \\assert(coroutine.status(co) == 'dead')
    );
}

fn runLua(lua: *api.State, source: []const u8) !void {
    lua.doString(source, .{}) catch |err| {
        const message = try lua.errorMessage();
        defer lua.allocator().free(message);
        std.debug.print("host test: {s}\n", .{message});
        return err;
    };
}

test "failed userdata construction never takes the host finalizer obligation" {
    const Payload = struct {
        finalized: *usize,
        fn release(self: *@This()) void {
            self.finalized.* += 1;
        }
    };
    for (0..12) |offset| {
        var failing = std.testing.FailingAllocator.init(a, .{});
        var lua = try api.State.init(failing.allocator(), .{});
        var finalized: usize = 0;
        var payload: Payload = .{ .finalized = &finalized };
        failing.fail_index = failing.alloc_index + offset;
        var success = false;
        if (lua.newUserdataPtr(Payload, &payload, .{ .finalizer = Payload.release })) |result| {
            var handle = result;
            handle.deinit();
            success = true;
        } else |_| {}
        lua.deinit();
        try std.testing.expectEqual(@as(usize, if (success) 1 else 0), finalized);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

test "warnings go to stderr or the host warning handler" {
    const Collector = struct {
        messages: std.ArrayList(u8) = .empty,

        fn emit(context: ?*anyopaque, message: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.messages.appendSlice(std.testing.allocator, message) catch {};
            self.messages.append(std.testing.allocator, '|') catch {};
        }
    };
    var collector: Collector = .{};
    defer collector.messages.deinit(std.testing.allocator);
    {
        var lua = try api.State.init(std.testing.allocator, .{ .capabilities = .{ .io = .{ .warning_handler = .{ .context = &collector, .emit = Collector.emit } } } });
        defer lua.deinit();
        try lua.doString(
            \\warn("off by default")
            \\warn("@on")
            \\warn("a", "b")
            \\setmetatable({}, { __gc = function() error("gc", 0) end })
            \\collectgarbage()
            \\warn("@off")
            \\warn("hidden")
            \\KEEP = setmetatable({}, { __gc = function() error("closing", 0) end })
        , .{});
        lua.setWarnings(true);
        try lua.doString("warn('again')", .{});
    }
    try std.testing.expectEqualStrings("ab|error in __gc (gc)|again|error in __gc (closing)|", collector.messages.items);

    var buffer: [128]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);
    var lua = try api.State.init(std.testing.allocator, .{ .capabilities = .{ .io = .{ .stderr = &stderr, .warnings = true } } });
    defer lua.deinit();
    try lua.doString("warn('hi', 1)", .{});
    try std.testing.expectEqualStrings("Lua warning: hi1\n", stderr.buffered());
}

test "userdata __gc metamethods run before host finalizers" {
    const Item = struct {
        log: *std.ArrayList(u8),

        fn finalize(self: *@This()) void {
            self.log.appendSlice(std.testing.allocator, "host;") catch {};
        }
    };
    const Counted = struct {
        hits: *usize,

        pub fn __gc(self: *@This()) void {
            self.hits.* += 1;
        }
    };
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(std.testing.allocator);
    var hits: usize = 0;
    {
        var lua = try api.State.init(std.testing.allocator, .{});
        defer lua.deinit();
        try lua.doString(
            \\events = {}
            \\meta = { __gc = function(u) events[#events + 1] = "lua"; saved = u end }
        , .{});
        var meta = try lua.getGlobal("meta", api.Table);
        defer meta.deinit();
        var item = try lua.newUserdata(Item, .{ .log = &log }, .{ .metatable = meta, .finalizer = Item.finalize });
        item.deinit();
        try lua.collect();
        try lua.doString("assert(#events == 1 and saved ~= nil)", .{});
        try std.testing.expectEqualStrings("", log.items);
        try lua.doString("saved = nil", .{});
        try lua.collect();
        try lua.collect();
        try lua.doString("assert(#events == 1)", .{});
        try std.testing.expectEqualStrings("host;", log.items);

        var counted = try lua.newUserdataAuto(Counted, .{ .hits = &hits }, .{});
        counted.deinit();
        try lua.collect();
        try std.testing.expectEqual(@as(usize, 1), hits);

        var kept = try lua.newUserdataAuto(Counted, .{ .hits = &hits }, .{});
        try lua.setGlobal("kept", kept);
        kept.deinit();
    }
    try std.testing.expectEqual(@as(usize, 2), hits);
}

test "os.exit in a finalizer stops deinit finalizers and reaches the exit callback" {
    const Host = struct {
        exit_code: ?i32 = null,

        fn execute(_: ?*anyopaque, _: []const u8) anyerror!api.ProcessResult {
            return .{ .status = .exit, .code = 0 };
        }

        fn exit(context: ?*anyopaque, code: i32, _: bool) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.exit_code = code;
        }
    };
    var host: Host = .{};
    var buffer: [64]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&buffer);
    {
        var lua = try api.State.init(std.testing.allocator, .{
            .stdlib = .full,
            .capabilities = .{
                .io = .{ .stdout = &stdout },
                .process = .{ .custom = .{ .context = &host, .execute = Host.execute, .exit = Host.exit } },
            },
        });
        defer lua.deinit();
        try lua.doString(
            \\A = setmetatable({}, { __gc = function() print("older") end })
            \\B = setmetatable({}, { __gc = function() print("exit") os.exit(7) end })
            \\C = setmetatable({}, { __gc = function() print("newest") end })
        , .{});
    }
    try std.testing.expectEqual(@as(?i32, 7), host.exit_code);
    try std.testing.expectEqualStrings("newest\nexit\n", stdout.buffered());
}
