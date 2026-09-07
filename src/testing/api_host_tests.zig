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
                try ctx.state().collect();
            }
            var callback = try ctx.arg(1, api.Function);
            defer callback.deinit();
            try ctx.callNonYielding(callback, .{}, void);
            try ctx.state().collect();
        }
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
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

test "non-yielding callback stays on the current thread and unwinds before returning errors" {
    const Host = struct {
        fn call(ctx: *api.Context) !void {
            const thread = ctx.threadIdentity();
            var callback = try ctx.arg(0, api.Function);
            defer callback.deinit();
            ctx.callNonYielding(callback, .{}, void) catch |err| {
                // __close has run before the host can release its lock.
                try std.testing.expect(try ctx.state().getGlobal("closed", bool));
                try std.testing.expectEqual(thread, ctx.threadIdentity());
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
