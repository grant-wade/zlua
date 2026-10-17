const std = @import("std");
const api = @import("../api.zig");
const Context = api.Context;
const Function = api.Function;
const Ref = api.Ref;
const State = api.State;
const Table = api.Table;
const Tuple = api.Tuple;
const Userdata = api.Userdata;

fn expectProtectedErrorContains(lua: *State, function: Function, needle: []const u8) !void {
    const result = try function.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, needle) != null);
        },
    }
}

test "api typed host callback can create userdata through context" {
    const Budget = struct {
        remaining: i64,

        fn spend(self: *@This(), amount: i64) i64 {
            self.remaining = @max(self.remaining - amount, 0);
            return self.remaining;
        }
    };
    const Callbacks = struct {
        fn newBudget(ctx: *Context, amount: i64) !Userdata(Budget) {
            var budget = try ctx.state().newUserdata(Budget, .{ .remaining = amount }, .{});
            errdefer budget.deinit();
            try budget.method("spend", Budget.spend);
            return budget;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_budget = try lua.registerTyped("new_budget", Callbacks.newBudget);
    defer new_budget.deinit();
    try lua.setGlobal("new_budget", new_budget);

    var chunk = try lua.loadString(
        \\local budget = new_budget(25)
        \\assert(type(budget) == 'userdata')
        \\assert(budget:spend(7) == 18)
        \\assert(budget:spend(20) == 0)
        \\return budget
    , .{ .name = "=api-21.4-typed-userdata" });
    defer chunk.deinit();

    var budget = try chunk.call(.{}, Userdata(Budget));
    defer budget.deinit();
    try std.testing.expectEqual(@as(i64, 0), (try budget.ptr()).remaining);
}

test "api userdata methods receive typed Zig pointers" {
    const Counter = struct {
        value: i64,

        fn inc(self: *@This(), amount: i64) i64 {
            self.value += amount;
            return self.value;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdata(Counter, .{ .value = 0 }, .{});
    defer counter.deinit();
    try counter.method("inc", Counter.inc);
    try lua.setGlobal("counter", counter);

    try lua.doString(
        \\assert(type(counter) == 'userdata')
        \\assert(counter:inc(2) == 2)
        \\assert(counter:inc(3) == 5)
    , .{ .name = "=api-21.5-counter" });

    try std.testing.expectEqual(@as(i64, 5), (try counter.ptr()).value);
}

test "api auto userdata binding installs receiver methods" {
    const Counter = struct {
        value: i64,

        pub fn inc(self: *@This(), ctx: *Context, amount: i64) !i64 {
            try std.testing.expectEqual(@as(usize, 2), ctx.argCount());
            self.value += amount;
            return self.value;
        }

        pub fn get(self: *const @This()) i64 {
            return self.value;
        }

        pub fn clear(self: *@This()) !void {
            self.value = 0;
        }

        pub fn __tostring(self: *const @This()) []const u8 {
            _ = self;
            return "Counter";
        }

        pub fn helper(amount: i64) i64 {
            return amount;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdataAuto(Counter, .{ .value = 0 }, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);

    try lua.doString(
        \\assert(type(counter) == 'userdata')
        \\assert(counter:inc(2) == 2)
        \\assert(counter:get() == 2)
        \\assert(tostring(counter) == 'Counter')
        \\counter:clear()
        \\assert(counter:get() == 0)
        \\assert(counter.helper == nil)
    , .{ .name = "=api-auto-userdata" });

    try std.testing.expectEqual(@as(i64, 0), (try counter.ptr()).value);
}

test "api auto userdata pointer wrappers bind methods" {
    const Counter = struct {
        value: i64,

        pub fn inc(self: *@This(), amount: i64) i64 {
            self.value += amount;
            return self.value;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var backing = Counter{ .value = 10 };
    var counter = try lua.newUserdataPtrAuto(Counter, &backing, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);

    try lua.doString("assert(counter:inc(32) == 42)", .{ .name = "=api-auto-userdata-ptr" });
    try std.testing.expectEqual(@as(i64, 42), backing.value);
}

test "api userdata initializer with returns auto-bound userdata" {
    const Budget = struct {
        remaining: i64,
        label: []const u8,

        pub fn init(ctx: *Context, amount: i64, label: []const u8) !@This() {
            try std.testing.expectEqual(@as(usize, 2), ctx.argCount());
            return .{ .remaining = amount, .label = label };
        }

        pub fn spend(self: *@This(), amount: i64) i64 {
            self.remaining = @max(self.remaining - amount, 0);
            return self.remaining;
        }

        pub fn name(self: *const @This()) []const u8 {
            return self.label;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_budget = try lua.registerUserdataInitializerWith(Budget, "new_budget", Budget.init, .{});
    defer new_budget.deinit();
    try lua.setGlobal("new_budget", new_budget);

    var chunk = try lua.loadString(
        \\local budget = new_budget(25, 'ops')
        \\assert(type(budget) == 'userdata')
        \\assert(budget:name() == 'ops')
        \\assert(budget:spend(7) == 18)
        \\return budget
    , .{ .name = "=api-userdata-initializer-with" });
    defer chunk.deinit();

    var budget = try chunk.call(.{}, Userdata(Budget));
    defer budget.deinit();
    try std.testing.expectEqual(@as(i64, 18), (try budget.ptr()).remaining);
}

test "api userdata initializer with accepts plain initializer functions" {
    const Counter = struct {
        value: i64,

        pub fn init(value: i64) @This() {
            return .{ .value = value };
        }

        pub fn get(self: *const @This()) i64 {
            return self.value;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_counter = try lua.registerUserdataInitializerWith(Counter, "new_counter", Counter.init, .{});
    defer new_counter.deinit();
    try lua.setGlobal("new_counter", new_counter);

    try lua.doString("assert(new_counter(42):get() == 42)", .{ .name = "=api-userdata-initializer-plain" });
}

test "api userdata initializer with argument errors become Lua errors" {
    const Counter = struct {
        value: i64,

        pub fn init(value: i64) @This() {
            return .{ .value = value };
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_counter = try lua.registerUserdataInitializerWith(Counter, "new_counter", Counter.init, .{});
    defer new_counter.deinit();
    try lua.setGlobal("new_counter", new_counter);

    var chunk = try lua.loadString("new_counter('bad')", .{ .name = "=api-userdata-initializer-arg-error" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "new_counter") != null);
            try std.testing.expect(std.mem.indexOf(u8, message, "number") != null);
        },
    }
}

test "api userdata initializer with can raise Lua errors" {
    const Counter = struct {
        value: i64,

        pub fn init(ctx: *Context, value: i64) !@This() {
            if (value < 0) return ctx.raise("negative counter");
            return .{ .value = value };
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_counter = try lua.registerUserdataInitializerWith(Counter, "new_counter", Counter.init, .{});
    defer new_counter.deinit();
    try lua.setGlobal("new_counter", new_counter);

    var chunk = try lua.loadString("new_counter(-1)", .{ .name = "=api-userdata-initializer-raise" });
    defer chunk.deinit();

    try expectProtectedErrorContains(&lua, chunk, "negative counter");
}

test "api auto userdata binding skips non receiver declarations" {
    const Other = struct { value: i64 };
    const Fixture = struct {
        value: i64,

        pub const tag = "not a method";

        pub fn ok(self: *const @This()) i64 {
            return self.value;
        }

        pub fn static() i64 {
            return 1;
        }

        pub fn wrongReceiver(self: *Other) i64 {
            return self.value;
        }

        pub fn wrongConstReceiver(self: *const Other) i64 {
            return self.value;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var fixture = try lua.newUserdataAuto(Fixture, .{ .value = 7 }, .{});
    defer fixture.deinit();
    try lua.setGlobal("fixture", fixture);

    try lua.doString(
        \\assert(fixture:ok() == 7)
        \\assert(fixture.tag == nil)
        \\assert(fixture.static == nil)
        \\assert(fixture.wrongReceiver == nil)
        \\assert(fixture.wrongConstReceiver == nil)
    , .{ .name = "=api-auto-userdata-skips" });
}

test "api userdata method context injection works in later positions" {
    const Counter = struct {
        value: i64,

        pub fn middle(self: *@This(), amount: i64, ctx: *Context, label: []const u8) !i64 {
            try std.testing.expectEqual(@as(usize, 3), ctx.argCount());
            try std.testing.expectEqualStrings("middle", label);
            self.value += amount;
            return self.value;
        }

        pub fn trailing(self: *@This(), amount: i64, label: []const u8, ctx: *Context) !i64 {
            try std.testing.expectEqual(@as(usize, 3), ctx.argCount());
            try std.testing.expectEqualStrings("trailing", label);
            self.value += amount;
            return self.value;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdataAuto(Counter, .{ .value = 0 }, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);

    try lua.doString(
        \\assert(counter:middle(2, 'middle') == 2)
        \\assert(counter:trailing(3, 'trailing') == 5)
    , .{ .name = "=api-userdata-context-positions" });

    try std.testing.expectEqual(@as(i64, 5), (try counter.ptr()).value);
}

test "api userdata pointer wrappers and Context.arg typed reads" {
    const Counter = struct {
        value: i64,
    };
    const Callbacks = struct {
        fn add(ctx: *Context) !void {
            const counter = try ctx.arg(0, *Counter);
            const amount = try ctx.arg(1, i64);
            counter.value += amount;
            try ctx.returnValues(counter.value);
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var backing = Counter{ .value = 10 };
    var counter = try lua.newUserdataPtr(Counter, &backing, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);
    var add_counter = try lua.register("add_counter", Callbacks.add);
    defer add_counter.deinit();
    try lua.setGlobal("add_counter", add_counter);

    try lua.doString("assert(add_counter(counter, 32) == 42)", .{ .name = "=api-21.5-ptr" });
    try std.testing.expectEqual(@as(i64, 42), backing.value);
}

test "api userdata wrong type errors are clear" {
    const Counter = struct { value: i64 };
    const Other = struct { value: i64 };
    const Callbacks = struct {
        fn needCounter(ctx: *Context) !void {
            _ = try ctx.arg(0, *Counter);
            try ctx.returnValues(.{});
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var other = try lua.newUserdata(Other, .{ .value = 1 }, .{});
    defer other.deinit();
    try lua.setGlobal("other", other);
    var need_counter = try lua.register("need_counter", Callbacks.needCounter);
    defer need_counter.deinit();
    try lua.setGlobal("need_counter", need_counter);

    var chunk = try lua.loadString("need_counter(other)", .{ .name = "=api-21.5-wrong-userdata" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "need_counter") != null);
            try std.testing.expect(std.mem.indexOf(u8, message, @typeName(Counter)) != null);
            try std.testing.expect(std.mem.indexOf(u8, message, @typeName(Other)) != null);
        },
    }
}

test "api userdata method wrong receiver errors are clear" {
    const Counter = struct {
        value: i64,

        pub fn inc(self: *@This(), amount: i64) i64 {
            self.value += amount;
            return self.value;
        }
    };
    const Other = struct { value: i64 };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdataAuto(Counter, .{ .value = 0 }, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);

    var other = try lua.newUserdata(Other, .{ .value = 1 }, .{});
    defer other.deinit();
    try lua.setGlobal("other", other);

    var chunk = try lua.loadString("counter.inc(other, 1)", .{ .name = "=api-userdata-wrong-receiver" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "inc") != null);
            try std.testing.expect(std.mem.indexOf(u8, message, @typeName(Counter)) != null);
            try std.testing.expect(std.mem.indexOf(u8, message, @typeName(Other)) != null);
        },
    }
}

test "api userdata finalizers run under forced GC" {
    const Tracker = struct {
        finalized: *usize,

        fn finalize(self: *@This()) void {
            self.finalized.* += 1;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var finalized: usize = 0;
    {
        var tracker = try lua.newUserdata(Tracker, .{ .finalized = &finalized }, .{ .finalizer = Tracker.finalize });
        tracker.deinit();
    }

    try lua.collect();
    try std.testing.expectEqual(@as(usize, 1), finalized);
}

test "api userdata close metamethod runs for to-be-closed locals" {
    const Closer = struct {
        closed: *usize,

        fn close(self: *@This()) void {
            self.closed.* += 1;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var closed: usize = 0;
    var closer = try lua.newUserdata(Closer, .{ .closed = &closed }, .{});
    defer closer.deinit();
    try closer.metamethod("__close", Closer.close);
    try lua.setGlobal("closer", closer);

    try lua.doString(
        \\do
        \\  local scoped <close> = closer
        \\end
    , .{ .name = "=api-21.5-close" });
    try std.testing.expectEqual(@as(usize, 1), closed);
}

test "api userdata pairs and ipairs use explicit and automatic metamethods" {
    const Sequence = struct {
        values: [4]?bool,
        fail: bool = false,

        pub fn __index(self: *const @This(), ctx: *Context, index: i64) !?bool {
            if (self.fail) return ctx.raise("index failed");
            if (index < 1 or index > self.values.len) return null;
            return self.values[@intCast(index - 1)];
        }

        pub fn __pairs(self: *const @This(), ctx: *Context) !@Tuple(&.{ Ref, Table }) {
            if (self.fail) return ctx.raise("pairs failed");
            var table = try ctx.state().createTable(.{});
            errdefer table.deinit();
            for (self.values, 1..) |value, index| try table.set(index, value);
            return .{ try ctx.state().getGlobal("next", Ref), table };
        }
    };
    var lua = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer lua.deinit();
    for ([_]bool{ false, true }) |automatic| {
        for ([_][4]?bool{
            .{ null, null, null, null },
            .{ false, true, null, null },
            .{ true, null, false, null },
        }) |values| {
            const payload: Sequence = .{ .values = values };
            var sequence = if (automatic)
                try lua.newUserdataAuto(Sequence, payload, .{})
            else
                try lua.newUserdata(Sequence, payload, .{});
            defer sequence.deinit();
            if (!automatic) {
                try sequence.metamethod("__index", Sequence.__index);
                try sequence.metamethod("__pairs", Sequence.__pairs);
            }
            try lua.setGlobal("sequence", sequence);
            var expected = try lua.createTable(.{});
            defer expected.deinit();
            for (values, 1..) |value, index| try expected.set(index, value);
            try lua.setGlobal("expected", expected);
            try lua.doString(
                \\assert(type(sequence) == 'userdata')
                \\assert(select('#', pairs(sequence)) == 4)
                \\local found = {}
                \\for k, v in pairs(sequence) do assert(v == expected[k]); found[k] = v end
                \\for k, v in pairs(expected) do assert(found[k] == v) end
                \\local iter, state, key = ipairs(sequence)
                \\assert(state == sequence and key == 0)
                \\local count = 0
                \\for k, v in ipairs(sequence) do
                \\  count = count + 1
                \\  assert(k == count and v == expected[k])
                \\  local direct_k, direct_v = iter(state, key)
                \\  assert(direct_k == k and direct_v == v)
                \\  key = k
                \\end
                \\assert(expected[count + 1] == nil)
                \\assert(select('#', iter(state, key)) == 1 and iter(state, key) == nil)
            , .{});
        }
    }
    var failing = try lua.newUserdataAuto(Sequence, .{ .values = @splat(null), .fail = true }, .{});
    defer failing.deinit();
    try lua.setGlobal("failing", failing);
    try lua.doString(
        \\local ok, err = pcall(pairs, failing)
        \\assert(not ok and err == 'pairs failed', tostring(err))
        \\ok, err = pcall(function() for k, v in pairs(failing) do end end)
        \\assert(not ok and err == 'pairs failed', tostring(err))
        \\local iter, state, key = ipairs(failing)
        \\ok, err = pcall(iter, state, key)
        \\assert(not ok and err == 'index failed', tostring(err))
        \\ok, err = pcall(function() for k, v in ipairs(failing) do end end)
        \\assert(not ok and err == 'index failed', tostring(err))
    , .{});
}

test "api userdata table index and Lua iteration metamethods" {
    var lua = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer lua.deinit();
    var userdata = try lua.newUserdata(u8, 0, .{});
    defer userdata.deinit();
    try lua.setGlobal("userdata", userdata);
    try lua.doString(
        \\local mt = getmetatable(userdata)
        \\mt.__index = {false, 22, [4] = 44}
        \\local count = 0
        \\for k, v in ipairs(userdata) do count = count + 1; assert(v == mt.__index[k]) end
        \\assert(count == 2)
        \\local iter, state, key = ipairs(userdata)
        \\assert(iter(state, 0) == 1 and select(2, iter(state, 0)) == false)
        \\assert(select('#', iter(state, 2)) == 1 and iter(state, 2) == nil)
        \\assert(not pcall(function() for k, v in pairs(userdata) do end end))
        \\mt.__pairs = function(self)
        \\  assert(self == userdata)
        \\  coroutine.yield('pairs setup')
        \\  return next, mt.__index, nil, nil, 'discarded'
        \\end
        \\local co = coroutine.create(function()
        \\  local count = 0
        \\  for k, v in pairs(userdata) do count = count + 1 end
        \\  return count
        \\end)
        \\local ok, value = coroutine.resume(co)
        \\assert(ok and value == 'pairs setup')
        \\ok, value = coroutine.resume(co)
        \\assert(ok and value == 3)
        \\mt.__index = function() return coroutine.yield('forbidden') end
        \\for _, direct in ipairs({false, true}) do
        \\  co = coroutine.create(function()
        \\    if direct then return iter(userdata, 0) end
        \\    for k, v in ipairs(userdata) do end
        \\  end)
        \\  ok, value = coroutine.resume(co)
        \\  assert(not ok and type(value) == 'string')
        \\end
    , .{});
}
