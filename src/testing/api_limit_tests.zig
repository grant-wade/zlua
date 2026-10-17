const std = @import("std");
const builtin = @import("builtin");
const api = @import("../root.zig");
const entry_mod = @import("../runtime/entry.zig");
const a = std.testing.allocator;

var lua_started: std.atomic.Value(bool) = .init(false);

fn markReady(_: *api.Context) !void {
    lua_started.store(true, .release);
}

var trigger_handle: ?api.InterruptHandle = null;

fn trigger(_: *api.Context) !void {
    trigger_handle.?.interrupt();
}

fn initWithTrigger() !api.State {
    var lua = try api.State.init(a, .{});
    errdefer lua.deinit();
    var function = try lua.register("trigger", trigger);
    defer function.deinit();
    try lua.setGlobal("trigger", function);
    trigger_handle = try lua.interruptHandle();
    return lua;
}

const Watchdog = struct {
    handle: api.InterruptHandle,

    fn run(self: *const Watchdog) void {
        while (!lua_started.load(.acquire)) std.atomic.spinLoopHint();
        self.handle.interrupt();
    }
};

fn initWithReady(options: api.Options) !api.State {
    var lua = try api.State.init(a, options);
    errdefer lua.deinit();
    var ready = try lua.register("ready", markReady);
    defer ready.deinit();
    try lua.setGlobal("ready", ready);
    return lua;
}

fn runInterrupted(lua: *api.State, source: []const u8) !void {
    lua_started.store(false, .release);
    var watchdog = Watchdog{ .handle = try lua.interruptHandle() };
    const thread = try std.Thread.spawn(.{}, Watchdog.run, .{&watchdog});
    const result = lua.doString(source, .{ .name = "=interrupted" });
    lua_started.store(true, .release);
    thread.join();
    try std.testing.expectError(error.Interrupted, result);
    try std.testing.expect(!lua.isInterruptPending());
}

fn skipWithoutThreads() !void {
    if (builtin.single_threaded or builtin.target.cpu.arch.isWasm()) return error.SkipZigTest;
}

test "interrupt from another thread stops tight loops and leaves the state usable" {
    try skipWithoutThreads();
    var lua = try initWithReady(.{});
    defer lua.deinit();

    try runInterrupted(&lua, "ready() while true do end");
    try runInterrupted(&lua, "ready() local i = 0 while true do i = i + 1 end");
    try runInterrupted(&lua, "counter = 0 ready() while true do counter = counter + 1 end");
    try runInterrupted(&lua, "local function f(n) if n == 0 then return 0 end return f(n - 1) + f(n - 1) end ready() f(60)");

    try lua.doString("after = 40 + 2", .{});
    try std.testing.expectEqual(@as(i64, 42), try lua.getGlobal("after", i64));
    try std.testing.expect(try lua.getGlobal("counter", i64) >= 0);
}

test "interrupt cannot be caught by pcall, xpcall, or coroutines" {
    try skipWithoutThreads();
    var lua = try initWithReady(.{});
    defer lua.deinit();

    try runInterrupted(&lua, "ready() while true do pcall(function() end) end");
    try runInterrupted(&lua, "ready() while true do pcall(function() while true do end end) end");
    try runInterrupted(&lua, "ready() while true do xpcall(function() while true do end end, function(e) return e end) end");
    try runInterrupted(&lua,
        \\local co = coroutine.wrap(function() while true do coroutine.yield() end end)
        \\ready()
        \\while true do co() end
    );
    try runInterrupted(&lua,
        \\ready()
        \\while true do
        \\  local ok = coroutine.resume(coroutine.create(function() while true do end end))
        \\  caught = not ok
        \\end
    );
    try std.testing.expectEqual(api.Value.nil, try lua.getGlobal("caught", api.Value));
    try runInterrupted(&lua,
        \\local co = coroutine.create(function() ready() while true do end end)
        \\while true do pcall(coroutine.resume, co) end
    );
    try lua.doString("assert(pcall(function() return 1 end))", .{});
}

test "interrupt stops long-running library functions" {
    try skipWithoutThreads();
    var lua = try initWithReady(.{ .limits = .{ .max_memory = 512 * 1024 * 1024 } });
    defer lua.deinit();

    try runInterrupted(&lua, "ready() local s = string.rep('x', (1 << 31) - 1)");
    try runInterrupted(&lua, "local s = string.rep('a', 1 << 16) ready() while true do s:gsub('a', 'b') end");
    try runInterrupted(&lua, "local s = string.rep('a', 1 << 16) .. 'c' ready() while true do s:find('a-a-a-b') end");
    try lua.doString("assert(('ab'):rep(3) == 'ababab')", .{});
}

test "pending interrupts stop library functions called directly by the host" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    const handle = try lua.interruptHandle();
    const raw = &lua.raw_state;
    const string_lib = raw.getGlobal("string").table;
    const table_lib = raw.getGlobal("table").table;
    const rep = string_lib.get(.{ .string = try raw.intern("rep") });
    const concat = table_lib.get(.{ .string = try raw.intern("concat") });
    const sort = table_lib.get(.{ .string = try raw.intern("sort") });
    var items = try lua.createTable(.{});
    defer items.deinit();
    for (0..8) |index| try items.append(@as(i64, @intCast(8 - index)));
    try lua.setGlobal("items", items);
    const items_value = raw.getGlobal("items");

    handle.interrupt();
    try std.testing.expectError(error.Interrupted, entry_mod.callFunction(raw, rep, &.{ .{ .string = try raw.intern("x") }, .{ .integer = 1 << 20 } }));
    try std.testing.expect(!lua.isInterruptPending());
    handle.interrupt();
    try std.testing.expectError(error.Interrupted, entry_mod.callFunction(raw, concat, &.{items_value}));
    try std.testing.expect(!lua.isInterruptPending());
    handle.interrupt();
    try std.testing.expectError(error.Interrupted, entry_mod.callFunction(raw, sort, &.{items_value}));
    try std.testing.expect(!lua.isInterruptPending());

    const values = try entry_mod.callFunction(raw, rep, &.{ .{ .string = try raw.intern("x") }, .{ .integer = 3 } });
    defer lua.allocator().free(values);
    try std.testing.expectEqualStrings("xxx", values[0].string);
}

test "interrupt requested while idle applies to the next run unless cleared" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    const handle = try lua.interruptHandle();
    const copy = handle;

    copy.interrupt();
    try std.testing.expect(lua.isInterruptPending());
    try std.testing.expect(handle.isPending());
    try std.testing.expectError(error.Interrupted, lua.doString("while true do end", .{}));
    try std.testing.expect(!lua.isInterruptPending());

    handle.interrupt();
    lua.clearInterrupt();
    try lua.doString("local n = 0 for i = 1, 10000 do n = n + i end assert(n == 50005000)", .{});

    var loop = try lua.loadString("while true do end", .{});
    defer loop.deinit();
    handle.interrupt();
    try std.testing.expectError(error.Interrupted, loop.protectedCall(.{}, void));
}

test "interrupt skips pending close handlers and keeps captured locals" {
    var lua = try initWithTrigger();
    defer lua.deinit();
    try lua.doString(
        \\function run()
        \\  local guard <close> = setmetatable({}, { __close = function() closed = true end })
        \\  local captured = 10
        \\  get = function() return captured end
        \\  captured = 11
        \\  trigger()
        \\  while true do end
        \\end
    , .{});
    var run = try lua.getGlobal("run", api.Function);
    defer run.deinit();
    try std.testing.expectError(error.Interrupted, run.call(.{}, void));
    try lua.doString("assert(closed == nil) assert(get() == 11)", .{});
}

test "interrupt propagates through host callbacks that call back into Lua" {
    const Callbacks = struct {
        var swallowed: bool = false;

        fn swallow(ctx: *api.Context) !void {
            var function = try ctx.arg(0, api.Function);
            defer function.deinit();
            _ = function.call(.{}, void) catch |err| {
                try std.testing.expectEqual(error.Interrupted, err);
                swallowed = true;
                return;
            };
        }
    };
    var lua = try initWithTrigger();
    defer lua.deinit();
    var swallow = try lua.register("swallow", Callbacks.swallow);
    defer swallow.deinit();
    try lua.setGlobal("swallow", swallow);

    try std.testing.expectError(error.Interrupted, lua.doString("swallow(function() trigger() while true do end end) after_swallow = true while true do end", .{}));
    try std.testing.expect(Callbacks.swallowed);
    try std.testing.expectEqual(api.Value.nil, try lua.getGlobal("after_swallow", api.Value));
    try std.testing.expect(!lua.isInterruptPending());
}

test "interrupt handles survive reset" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("value = 1", .{});
    var snapshot = try lua.snapshot(a);
    defer snapshot.deinit();
    const handle = try lua.interruptHandle();
    try lua.reset();
    handle.interrupt();
    try std.testing.expectError(error.Interrupted, lua.doString("while true do end", .{}));
    try lua.reset();
    try std.testing.expectEqual(@as(i64, 1), try lua.getGlobal("value", i64));

    var worker = try snapshot.newState(a);
    defer worker.deinit();
    try worker.doString("assert(value == 1)", .{});
}

fn expectLimitError(result: anytype, lua: *api.State) !void {
    try std.testing.expectError(error.LuaError, result);
    const message = try lua.errorMessage();
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "instruction limit exceeded") != null);
}

test "per-call instruction budgets bound one call and keep the state usable" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\function spin() while true do end end
        \\function guarded() while true do pcall(spin) end end
        \\function resumer()
        \\  local co = coroutine.create(function() while true do coroutine.yield() end end)
        \\  while true do coroutine.resume(co) end
        \\end
        \\function count(n) local total = 0 for i = 1, n do total = total + i end return total end
        \\handled = 0
        \\function handled_spin()
        \\  local ok, e = xpcall(spin, function(m) handled = handled + 1; return "handled" end)
        \\  return e
        \\end
    , .{});
    var spin = try lua.getGlobal("spin", api.Function);
    defer spin.deinit();
    var guarded = try lua.getGlobal("guarded", api.Function);
    defer guarded.deinit();
    var resumer = try lua.getGlobal("resumer", api.Function);
    defer resumer.deinit();
    var count = try lua.getGlobal("count", api.Function);
    defer count.deinit();

    try expectLimitError(spin.callWith(.{}, void, .{ .max_instructions = 1_000 }), &lua);
    try expectLimitError(guarded.callWith(.{}, void, .{ .max_instructions = 10_000 }), &lua);
    try expectLimitError(resumer.callWith(.{}, void, .{ .max_instructions = 10_000 }), &lua);

    const result = try spin.protectedCallWith(.{}, void, .{ .max_instructions = 500 });
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "instruction limit exceeded") != null);
        },
    }

    var handled_spin = try lua.getGlobal("handled_spin", api.Function);
    defer handled_spin.deinit();
    try expectLimitError(handled_spin.callWith(.{}, void, .{ .max_instructions = 1_000 }), &lua);
    try expectLimitError(spin.callWith(.{}, void, .{ .max_instructions = 1_000, .message_handler = count }), &lua);
    try std.testing.expectEqual(@as(i64, 0), try lua.getGlobal("handled", i64));

    try std.testing.expectEqual(@as(i64, 5050), try count.callWith(.{100}, i64, .{ .max_instructions = 10_000 }));
    try std.testing.expectEqual(@as(i64, 500500), try count.call(.{1000}, i64));
    try std.testing.expectEqual(@as(?u64, null), lua.instructionBudget().limit);
}

test "per-call budgets nest with the tighter budget and the state budget" {
    const Callbacks = struct {
        fn nested(ctx: *api.Context) !void {
            var function = try ctx.arg(0, api.Function);
            defer function.deinit();
            const budget = try ctx.arg(1, i64);
            const n = try ctx.arg(2, i64);
            const total = function.callWith(.{n}, i64, .{ .max_instructions = @intCast(budget) }) catch |err| switch (err) {
                error.LuaError => {
                    try ctx.returnValues(.{ false, "limit" });
                    return;
                },
                else => return err,
            };
            try ctx.returnValues(.{ true, total });
        }
    };
    var lua = try api.State.init(a, .{ .limits = .{ .max_instructions = 1_000_000 } });
    defer lua.deinit();
    var nested = try lua.register("nested", Callbacks.nested);
    defer nested.deinit();
    try lua.setGlobal("nested", nested);
    try lua.doString(
        \\function count(n) local total = 0 for i = 1, n do total = total + i end return total end
        \\function outer(budget, n)
        \\  local ok, value = nested(count, budget, n)
        \\  return ok, value
        \\end
    , .{});
    var outer = try lua.getGlobal("outer", api.Function);
    defer outer.deinit();
    const Pair = api.Tuple(&.{ bool, api.Value });

    var tight = try outer.callWith(.{ 100, 10_000 }, Pair, .{ .max_instructions = 100_000 });
    defer tight.deinit();
    try std.testing.expect(!tight.get(0));

    try expectLimitError(outer.callWith(.{ 1_000_000, 10_000 }, Pair, .{ .max_instructions = 1_000 }), &lua);

    var fits = try outer.callWith(.{ 100_000, 100 }, Pair, .{ .max_instructions = 100_000 });
    defer fits.deinit();
    try std.testing.expect(fits.get(0));
    try std.testing.expectEqual(api.Value{ .integer = 5050 }, fits.get(1));

    const used = lua.instructionBudget().used;
    try std.testing.expect(used > 1_000);
    var count = try lua.getGlobal("count", api.Function);
    defer count.deinit();
    try expectLimitError(count.callWith(.{100_000_000}, i64, .{ .max_instructions = std.math.maxInt(u64) }), &lua);
    try std.testing.expectEqual(@as(?u64, 0), lua.instructionBudget().remaining);
    lua.resetInstructionBudget();
    try std.testing.expectEqual(@as(i64, 55), try count.callWith(.{10}, i64, .{ .max_instructions = 1_000 }));
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("missing {s} in:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedSubstring;
    }
}

test "protected calls capture tracebacks at the error point" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\local function inner(x)
        \\  error("boom " .. x)
        \\end
        \\local function middle(x)
        \\  inner(x)
        \\  return 1
        \\end
        \\function outer(x)
        \\  middle(x)
        \\  return 1
        \\end
        \\function fail_table() error({ code = 7 }) end
    , .{ .name = "@app.lua" });
    var outer = try lua.getGlobal("outer", api.Function);
    defer outer.deinit();

    const result = try outer.protectedCallWith(.{1}, void, .{ .traceback = true });
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expectEqualStrings("app.lua:2: boom 1", message);
            try std.testing.expectEqualStrings("stack traceback:\n" ++
                "\t[C]: in global 'error'\n" ++
                "\tapp.lua:2: in upvalue 'inner'\n" ++
                "\tapp.lua:5: in upvalue 'middle'\n" ++
                "\tapp.lua:9: in function 'outer'", err.traceback().?);
        },
    }

    const plain = try outer.protectedCall(.{2}, void);
    switch (plain) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            try std.testing.expectEqual(@as(?[]const u8, null), err.traceback());
        },
    }

    var fail_table = try lua.getGlobal("fail_table", api.Function);
    defer fail_table.deinit();
    const table_result = try fail_table.protectedCallWith(.{}, void, .{ .traceback = true });
    switch (table_result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            var value = try err.value();
            defer value.deinit();
            try std.testing.expect(value == .table);
            try std.testing.expectEqual(@as(i64, 7), try value.table.get("code", i64));
            try expectContains(err.traceback().?, "\n\t[C]: in global 'error'\n\tapp.lua:12: in function 'fail_table'");
        },
    }

    try std.testing.expectError(error.LuaError, outer.callWith(.{3}, void, .{ .traceback = true }));
    var taken = lua.takeErrorValue().?;
    defer taken.deinit();
    try expectContains(taken.traceback().?, "app.lua:2: in upvalue 'inner'");
    try std.testing.expectError(error.LuaError, outer.callWith(.{4}, void, .{ .traceback = true }));
    try std.testing.expectError(error.LuaError, outer.callWith(.{5}, void, .{ .traceback = true }));
}

test "tracebacks name host callbacks, metamethods, fields, and methods" {
    const Callbacks = struct {
        fn fail(ctx: *api.Context) !void {
            return ctx.raise("host failure");
        }
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var fail = try lua.register("host_fail", Callbacks.fail);
    defer fail.deinit();
    try lua.setGlobal("host_fail", fail);
    try lua.doString(
        \\local object = {}
        \\function object:method() host_fail() end
        \\local meta = setmetatable({}, { __index = function(t, k) object:method() end })
        \\function run() local value = meta.missing end
        \\function sorted() table.sort({ 3, 2, 1 }, function(x, y) host_fail() end) end
        \\function tail() return run() end
    , .{ .name = "=cb.lua" });

    var run = try lua.getGlobal("run", api.Function);
    defer run.deinit();
    const result = try run.protectedCallWith(.{}, void, .{ .traceback = true });
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            try std.testing.expectEqualStrings("stack traceback:\n" ++
                "\t[C]: in global 'host_fail'\n" ++
                "\tcb.lua:2: in method 'method'\n" ++
                "\tcb.lua:3: in metamethod 'index'\n" ++
                "\tcb.lua:4: in function 'run'", err.traceback().?);
        },
    }

    var sorted = try lua.getGlobal("sorted", api.Function);
    defer sorted.deinit();
    const sort_result = try sorted.protectedCallWith(.{}, void, .{ .traceback = true });
    switch (sort_result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            try std.testing.expectEqualStrings("stack traceback:\n" ++
                "\t[C]: in global 'host_fail'\n" ++
                "\tcb.lua:5: in function <cb.lua:5>\n" ++
                "\t[C]: in field 'sort'\n" ++
                "\tcb.lua:5: in function 'sorted'", err.traceback().?);
        },
    }

    var tail = try lua.getGlobal("tail", api.Function);
    defer tail.deinit();
    const tail_result = try tail.protectedCallWith(.{}, void, .{ .traceback = true });
    switch (tail_result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            try expectContains(err.traceback().?, "cb.lua:4: in function 'run'\n\t(...tail calls...)");
        },
    }
}

test "tracebacks of deep recursion skip middle levels like Lua" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("function deep(n) if n == 0 then error('bottom') end deep(n - 1) end", .{ .name = "=deep.lua" });
    var deep = try lua.getGlobal("deep", api.Function);
    defer deep.deinit();
    const result = try deep.protectedCallWith(.{40}, void, .{ .traceback = true });
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            const text = err.traceback().?;
            try expectContains(text, "\n\t...\t(skipping 20 levels)\n");
            try std.testing.expectEqual(@as(usize, 22), std.mem.count(u8, text, "\n\t"));
        },
    }
}

test "protected call message handlers run on the failing frames" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.doString(
        \\function fail(x) local secret = x error("bad") end
        \\function handler(e)
        \\  local levels = 0
        \\  while debug.getinfo(levels + 1, "l") do levels = levels + 1 end
        \\  return { message = e, levels = levels }
        \\end
        \\function broken(e) error("again") end
    , .{ .name = "=handled.lua" });
    var fail = try lua.getGlobal("fail", api.Function);
    defer fail.deinit();
    var handler = try lua.getGlobal("handler", api.Function);
    defer handler.deinit();
    var broken = try lua.getGlobal("broken", api.Function);
    defer broken.deinit();

    const result = try fail.protectedCallWith(.{5}, void, .{ .message_handler = handler, .traceback = true });
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            var value = try err.value();
            defer value.deinit();
            try std.testing.expect(value == .table);
            const message = try value.table.get("message", []const u8);
            try std.testing.expectEqualStrings("handled.lua:1: bad", message);
            try std.testing.expect(try value.table.get("levels", i64) >= 2);
            try expectContains(err.traceback().?, "handled.lua:1: in function 'fail'");
        },
    }

    const broken_result = try fail.protectedCallWith(.{5}, void, .{ .message_handler = broken });
    switch (broken_result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expectEqualStrings("error in error handling", message);
        },
    }

    try std.testing.expectError(error.LuaError, fail.callWith(.{5}, void, .{ .message_handler = handler }));
    var taken = lua.takeErrorValue().?;
    defer taken.deinit();
    var taken_value = try taken.value();
    defer taken_value.deinit();
    try std.testing.expect(taken_value == .table);
}

test "tracebacks and handlers respect memory limits without leaking" {
    var lua = try api.State.init(a, .{ .limits = .{ .max_memory = 4 * 1024 * 1024 } });
    defer lua.deinit();
    try lua.doString("function fail() error('x') end", .{});
    var fail = try lua.getGlobal("fail", api.Function);
    defer fail.deinit();
    for (0..100) |_| {
        const result = try fail.protectedCallWith(.{}, void, .{ .traceback = true });
        switch (result) {
            .ok => return error.TestExpectedLuaError,
            .lua_error => |error_ref| {
                var err = error_ref;
                err.deinit();
            },
        }
    }
}

test "nil error objects reach hosts and message handlers as nil" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\function fail() error(nil) end
        \\function kind(e) return type(e) end
        \\co = coroutine.create(fail)
    , .{});
    var fail = try lua.getGlobal("fail", api.Function);
    defer fail.deinit();
    var kind = try lua.getGlobal("kind", api.Function);
    defer kind.deinit();

    const plain = try fail.protectedCall(.{}, void);
    switch (plain) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            var value = try err.value();
            defer value.deinit();
            try std.testing.expect(value == .nil);
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expectEqualStrings("<no error object>", message);
        },
    }
    try std.testing.expectError(error.LuaError, fail.call(.{}, void));
    const message = try lua.errorMessage();
    defer lua.allocator().free(message);
    try std.testing.expectEqualStrings("<no error object>", message);

    const handled = try fail.protectedCallWith(.{}, void, .{ .message_handler = kind });
    switch (handled) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            var value = try err.value();
            defer value.deinit();
            try std.testing.expectEqualStrings("nil", value.string);
        },
    }

    var co = try lua.getGlobal("co", api.Coroutine);
    defer co.deinit();
    const resumed = try co.protectedResume(.{}, void, void);
    switch (resumed) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            var value = try err.value();
            defer value.deinit();
            try std.testing.expectEqualStrings("<no error object>", value.string);
        },
    }
}
