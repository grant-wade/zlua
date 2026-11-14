const std = @import("std");
const api = @import("../api.zig");
const errorMessage = @import("api_expect.zig").errorMessage;
const callError = @import("api_expect.zig").callError;
const Context = api.Context;
const Function = api.Function;
const Ref = api.Ref;
const State = api.State;
const Table = api.Table;
const Userdata = api.Userdata;

fn expectProtectedErrorContains(lua: *State, function: Function, needle: []const u8) !void {
    var err = try callError(function, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, needle) != null);
}

test "api typed host callback can create userdata through context" {
    const Budget = struct {
        remaining: i64,

        pub fn spend(self: *@This(), amount: i64) i64 {
            self.remaining = @max(self.remaining - amount, 0);
            return self.remaining;
        }
    };
    const Callbacks = struct {
        fn newBudget(ctx: *Context, amount: i64) !Userdata(Budget) {
            return ctx.state().newUserdata(Budget, .{ .remaining = amount }, .{});
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_budget = try lua.newTypedFunction("new_budget", Callbacks.newBudget);
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

        pub fn inc(self: *@This(), amount: i64) i64 {
            self.value += amount;
            return self.value;
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdata(Counter, .{ .value = 0 }, .{});
    defer counter.deinit();
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdata(Counter, .{ .value = 0 }, .{});
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var backing = Counter{ .value = 10 };
    var counter = try lua.wrapUserdata(Counter, &backing, .{});
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_budget = try lua.newConstructor(Budget, "new_budget", Budget.init, .{});
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_counter = try lua.newConstructor(Counter, "new_counter", Counter.init, .{});
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_counter = try lua.newConstructor(Counter, "new_counter", Counter.init, .{});
    defer new_counter.deinit();
    try lua.setGlobal("new_counter", new_counter);

    var chunk = try lua.loadString("new_counter('bad')", .{ .name = "=api-userdata-initializer-arg-error" });
    defer chunk.deinit();

    var err = try callError(chunk, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "new_counter") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "number") != null);
}

test "api userdata initializer with can raise Lua errors" {
    const Counter = struct {
        value: i64,

        pub fn init(ctx: *Context, value: i64) !@This() {
            if (value < 0) return ctx.raise("negative counter");
            return .{ .value = value };
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var new_counter = try lua.newConstructor(Counter, "new_counter", Counter.init, .{});
    defer new_counter.deinit();
    try lua.setGlobal("new_counter", new_counter);

    var chunk = try lua.loadString("new_counter(-1)", .{ .name = "=api-userdata-initializer-raise" });
    defer chunk.deinit();

    try expectProtectedErrorContains(lua, chunk, "negative counter");
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var fixture = try lua.newUserdata(Fixture, .{ .value = 7 }, .{});
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdata(Counter, .{ .value = 0 }, .{});
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var backing = Counter{ .value = 10 };
    var counter = try lua.wrapUserdata(Counter, &backing, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);
    var add_counter = try lua.newFunction("add_counter", Callbacks.add);
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var other = try lua.newUserdata(Other, .{ .value = 1 }, .{});
    defer other.deinit();
    try lua.setGlobal("other", other);
    var need_counter = try lua.newFunction("need_counter", Callbacks.needCounter);
    defer need_counter.deinit();
    try lua.setGlobal("need_counter", need_counter);

    var chunk = try lua.loadString("need_counter(other)", .{ .name = "=api-21.5-wrong-userdata" });
    defer chunk.deinit();

    var err = try callError(chunk, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "need_counter") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, @typeName(Counter)) != null);
    try std.testing.expect(std.mem.indexOf(u8, message, @typeName(Other)) != null);
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var counter = try lua.newUserdata(Counter, .{ .value = 0 }, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);

    var other = try lua.newUserdata(Other, .{ .value = 1 }, .{});
    defer other.deinit();
    try lua.setGlobal("other", other);

    var chunk = try lua.loadString("counter.inc(other, 1)", .{ .name = "=api-userdata-wrong-receiver" });
    defer chunk.deinit();

    var err = try callError(chunk, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "inc") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, @typeName(Counter)) != null);
    try std.testing.expect(std.mem.indexOf(u8, message, @typeName(Other)) != null);
}

test "api userdata finalizers run under forced GC" {
    const Tracker = struct {
        finalized: *usize,

        fn finalize(self: *@This(), _: std.mem.Allocator) void {
            self.finalized.* += 1;
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
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

        pub fn __close(self: *@This()) void {
            self.closed.* += 1;
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var closed: usize = 0;
    var closer = try lua.newUserdata(Closer, .{ .closed = &closed }, .{});
    defer closer.deinit();
    try lua.setGlobal("closer", closer);

    try lua.doString(
        \\do
        \\  local scoped <close> = closer
        \\end
    , .{ .name = "=api-21.5-close" });
    try std.testing.expectEqual(@as(usize, 1), closed);
}

test "api userdata pairs and ipairs use bound metamethods" {
    const Sequence = struct {
        values: [4]?bool,
        fail: bool = false,

        pub fn __index(self: *const @This(), ctx: *Context, index: i64) !?bool {
            if (self.fail) return ctx.raise("index failed");
            if (index < 1 or index > self.values.len) return null;
            return self.values[@intCast(index - 1)];
        }

        pub fn __pairs(self: *const @This(), ctx: *Context) !struct { Ref, Table } {
            if (self.fail) return ctx.raise("pairs failed");
            var table = try ctx.state().newTable(.{});
            errdefer table.deinit();
            for (self.values, 1..) |value, index| try table.set(index, value);
            return .{ try ctx.state().getGlobal("next", Ref), table };
        }
    };
    const lua = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer lua.deinit();
    for ([_][4]?bool{
        .{ null, null, null, null },
        .{ false, true, null, null },
        .{ true, null, false, null },
    }) |values| {
        const payload: Sequence = .{ .values = values };
        var sequence = try lua.newUserdata(Sequence, payload, .{});
        defer sequence.deinit();
        try lua.setGlobal("sequence", sequence);
        var expected = try lua.newTable(.{});
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
    var failing = try lua.newUserdata(Sequence, .{ .values = @splat(null), .fail = true }, .{});
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
    const lua = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer lua.deinit();
    var userdata = try lua.newUserdata(u8, 0, .{});
    defer userdata.deinit();
    try lua.setGlobal("userdata", userdata);
    try lua.doString(
        \\local mt = debug.getmetatable(userdata)
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

test "api finalizers receive the state allocator and external bytes keep garbage bounded" {
    const Buffer = struct {
        bytes: []u8,

        var live: usize = 0;
        var peak: usize = 0;

        fn finalize(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
            live -= 1;
        }

        fn create(ctx: *Context) !void {
            const lua = ctx.state();
            const bytes = try lua.allocator().alloc(u8, 16);
            var ud = try lua.newUserdata(@This(), .{ .bytes = bytes }, .{ .finalizer = finalize, .external_bytes = 1024 * 1024 });
            defer ud.deinit();
            live += 1;
            peak = @max(peak, live);
            try ctx.returnValues(.{ud});
        }
    };
    Buffer.live = 0;
    Buffer.peak = 0;

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var create = try lua.newFunction("create", Buffer.create);
    defer create.deinit();
    try lua.setGlobal("create", create);

    try lua.doString("for _ = 1, 2000 do create() end", .{});
    try std.testing.expect(Buffer.peak < 64);
    const before = lua.raw_state.gc.known_total;
    try lua.collect();
    try lua.collect();
    try std.testing.expectEqual(@as(usize, 0), Buffer.live);
    try std.testing.expect(lua.raw_state.gc.known_total < before + 1024);
    try std.testing.expect(lua.raw_state.gc.known_total < 1024 * 1024);
}

test "api external bytes keep garbage bounded while a large heap collects" {
    var leak_check: std.heap.DebugAllocator(.{ .stack_trace_frames = 0 }) = .init;
    try collectExternalBytes(leak_check.allocator());
    try std.testing.expect(leak_check.deinit() == .ok);
}

fn collectExternalBytes(allocator: std.mem.Allocator) !void {
    const Buffer = struct {
        var live: usize = 0;
        var peak: usize = 0;

        pad: u8 = 0,

        fn finalize(_: *@This(), _: std.mem.Allocator) void {
            live -= 1;
        }

        fn create(ctx: *Context) !void {
            var ud = try ctx.state().newUserdata(@This(), .{}, .{ .finalizer = finalize, .external_bytes = 256 * 1024 });
            defer ud.deinit();
            live += 1;
            peak = @max(peak, live);
            try ctx.returnValues(.{ud});
        }
    };
    Buffer.live = 0;
    Buffer.peak = 0;

    const lua = try State.init(allocator, .{});
    defer lua.deinit();
    var create = try lua.newFunction("create", Buffer.create);
    defer create.deinit();
    try lua.setGlobal("create", create);

    try lua.doString(
        \\keep = {}
        \\for i = 1, 200000 do keep[i] = { i } end
        \\for _ = 1, 4000 do create() end
    , .{});
    try std.testing.expect(Buffer.peak < 800);
}

test "api setExternalBytes replaces the reported amount" {
    const Blob = struct { size: usize };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var blob = try lua.newUserdata(Blob, .{ .size = 1 }, .{});
    defer blob.deinit();

    const before = lua.raw_state.gc.known_total;
    try blob.setExternalBytes(4096);
    try std.testing.expectEqual(before + 4096, lua.raw_state.gc.known_total);
    try blob.setExternalBytes(1024);
    try std.testing.expectEqual(before + 1024, lua.raw_state.gc.known_total);
}

const DefinedCanvas = struct {
    width: i64,

    pub fn getWidth(self: *const @This()) i64 {
        return self.width;
    }

    pub fn setWidth(self: *@This(), width: i64) void {
        self.width = width;
    }

    pub fn copyFrom(self: *@This(), other: *const DefinedCanvas) void {
        self.width = other.width;
    }

    pub fn __tostring(self: *const @This()) []const u8 {
        return if (self.width > 0) "wide" else "empty";
    }
};

const DefinedMesh = struct {
    faces: i64,

    pub fn __len(self: *const @This()) i64 {
        return self.faces;
    }
};

test "api defined userdata share one metatable and one set of callbacks" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.defineUserdata(DefinedCanvas, .{ .name = "canvas", .expose_metatable = true });
    const callbacks = lua.callbacks.items.len;
    var a = try lua.newUserdata(DefinedCanvas, .{ .width = 1 }, .{});
    defer a.deinit();
    var b = try lua.newUserdata(DefinedCanvas, .{ .width = 2 }, .{});
    defer b.deinit();
    try std.testing.expectEqual(callbacks, lua.callbacks.items.len);

    try lua.setGlobal("a", a);
    try lua.setGlobal("b", b);
    try lua.doString(
        \\assert(getmetatable(a) == getmetatable(b))
        \\assert(getmetatable(a).__name == "canvas")
        \\assert(a:getWidth() == 1)
        \\b:setWidth(9)
        \\a:copyFrom(b)
        \\assert(a:getWidth() == 9)
        \\assert(tostring(a) == "wide")
    , .{});
    try std.testing.expectEqual(error.UserdataTypeDefined, lua.defineUserdata(DefinedCanvas, .{}));
}

test "api defined userdata names appear in argument errors" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.defineUserdata(DefinedCanvas, .{ .name = "canvas" });
    try lua.defineUserdata(DefinedMesh, .{ .name = "mesh" });
    var canvas = try lua.newUserdata(DefinedCanvas, .{ .width = 1 }, .{});
    defer canvas.deinit();
    try lua.setGlobal("canvas", canvas);
    var mesh = try lua.newUserdata(DefinedMesh, .{ .faces = 3 }, .{});
    defer mesh.deinit();
    try lua.setGlobal("mesh", mesh);

    try lua.doString(
        \\assert(#mesh == 3)
        \\local ok, message = pcall(canvas.copyFrom, canvas, mesh)
        \\assert(not ok and message:find("canvas expected, got mesh", 1, true), message)
        \\ok, message = pcall(canvas.copyFrom, canvas, {})
        \\assert(not ok and message:find("canvas expected, got table", 1, true), message)
        \\ok, message = pcall(canvas.getWidth, mesh)
        \\assert(not ok and message:find("canvas expected, got mesh", 1, true), message)
    , .{});
}

test "api defined userdata can take methods from another struct and a default name" {
    const Payload = struct { value: i64 };
    const Methods = struct {
        pub fn value(self: *const Payload) i64 {
            return self.value;
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try lua.defineUserdata(Payload, .{ .methods = Methods, .expose_metatable = true });
    var payload = try lua.newUserdata(Payload, .{ .value = 4 }, .{});
    defer payload.deinit();
    try lua.setGlobal("payload", payload);
    try lua.doString(
        \\assert(payload:value() == 4)
        \\assert(getmetatable(payload).__name:find("Payload", 1, true))
    , .{});
}

test "api auto userdata define their type once" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var first = try lua.newUserdata(DefinedCanvas, .{ .width = 1 }, .{});
    defer first.deinit();
    const callbacks = lua.callbacks.items.len;
    for (0..8) |_| {
        var more = try lua.newUserdata(DefinedCanvas, .{ .width = 2 }, .{});
        more.deinit();
    }
    var backing = DefinedCanvas{ .width = 3 };
    var pointer = try lua.wrapUserdata(DefinedCanvas, &backing, .{});
    defer pointer.deinit();
    try std.testing.expectEqual(callbacks, lua.callbacks.items.len);
    try lua.setGlobal("pointer", pointer);
    try lua.doString("assert(pointer:getWidth() == 3)", .{});
}

test "api userdata definitions follow snapshots and reset" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try lua.defineUserdata(DefinedCanvas, .{ .name = "canvas" });

    var snapshot = try lua.snapshot(std.testing.allocator);
    defer snapshot.deinit();
    const worker = try snapshot.newState(std.testing.allocator);
    defer worker.deinit();

    var canvas = try worker.newUserdata(DefinedCanvas, .{ .width = 5 }, .{});
    try worker.setGlobal("canvas", canvas);
    canvas.deinit();
    try worker.doString("assert(canvas:getWidth() == 5)", .{});

    try worker.defineUserdata(DefinedMesh, .{ .name = "mesh" });
    var mesh = try worker.newUserdata(DefinedMesh, .{ .faces = 2 }, .{});
    try worker.setGlobal("mesh", mesh);
    mesh.deinit();
    try worker.doString("assert(#mesh == 2)", .{});

    try worker.reset();
    try worker.defineUserdata(DefinedMesh, .{ .name = "mesh" });
    try std.testing.expectEqual(error.UserdataTypeDefined, worker.defineUserdata(DefinedCanvas, .{}));
    var again = try worker.newUserdata(DefinedCanvas, .{ .width = 6 }, .{});
    defer again.deinit();
    try worker.setGlobal("canvas", again);
    try worker.doString("assert(canvas:getWidth() == 6)", .{});
}

test "api userdata method raises an error naming the current Lua line" {
    const Scene = struct {
        pub fn text(self: *@This(), ctx: *Context, parent_id: i64) !void {
            _ = self;
            if (parent_id == 1) return;
            const line = ctx.currentLine() orelse 0;
            const message = try std.fmt.allocPrint(ctx.state().allocator(), "line {d}: parent_id not found", .{line});
            defer ctx.state().allocator().free(message);
            return ctx.raise(message);
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var scene = try lua.newUserdata(Scene, .{}, .{});
    defer scene.deinit();
    try lua.setGlobal("s", scene);

    var chunk = try lua.loadString(
        \\s:text(1)
        \\
        \\s:text(2)
    , .{ .name = "=config" });
    defer chunk.deinit();

    var err = try callError(chunk, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expectEqualStrings("line 3: parent_id not found", message);
}

test "api userdata lua declaration renames and leaves out methods" {
    const Buffer = struct {
        size: i64,
        open: bool = true,

        pub const lua = .{
            .deinit = .{ .skip = true },
            .release = .{ .skip = true },
            .length = .{ .key = "len" },
            .close = .{ .key = "__close" },
        };

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            _ = allocator;
            self.open = false;
        }

        pub fn release(self: *@This()) void {
            self.open = false;
        }

        pub fn length(self: *const @This()) i64 {
            return self.size;
        }

        pub fn close(self: *@This()) void {
            self.open = false;
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var buffer = try lua.newUserdata(Buffer, .{ .size = 3 }, .{});
    defer buffer.deinit();
    try lua.setGlobal("buffer", buffer);
    try lua.doString(
        \\assert(buffer:len() == 3)
        \\assert(buffer.deinit == nil and buffer.release == nil)
        \\assert(buffer.length == nil and buffer.close == nil)
    , .{});
    try std.testing.expect((try buffer.ptr()).open);
    try lua.doString("do local scoped <close> = buffer end", .{});
    try std.testing.expect(!(try buffer.ptr()).open);
}

test "api userdata lua_userdata declaration sets the options of the first use" {
    const Token = struct {
        id: i64,

        pub const lua_userdata = .{ .name = "token", .methods = struct {} };

        pub fn revoke(self: *@This()) void {
            self.id = 0;
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var owned = try lua.newUserdata(Token, .{ .id = 1 }, .{});
    defer owned.deinit();
    var backing = Token{ .id = 2 };
    var wrapped = try lua.wrapUserdata(Token, &backing, .{});
    defer wrapped.deinit();
    try lua.setGlobals(.{ .owned = owned, .wrapped = wrapped, .Token = Token });
    try lua.doString(
        \\assert(tostring(owned):find("^token: ") and tostring(wrapped):find("^token: "))
        \\assert(owned.revoke == nil and wrapped.revoke == nil)
        \\assert(Token.revoke and Token.lua_userdata == nil)
    , .{});
}

test "api userdata fields missing from the method table read as nil and fail when called" {
    const Counter = struct {
        n: i64 = 0,

        pub fn add(self: *@This(), amount: i64) i64 {
            self.n += amount;
            return self.n;
        }
    };
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var counter = try lua.newUserdata(Counter, .{}, .{});
    defer counter.deinit();
    try lua.setGlobal("counter", counter);

    try lua.doString(
        \\local total = 0
        \\for i = 1, 100 do
        \\  total = counter:add(i)
        \\  assert(counter.missing == nil and type(counter.add) == "function")
        \\end
        \\assert(total == 5050)
    , .{});
    try std.testing.expectEqual(@as(i64, 5050), (try counter.ptr()).n);

    try std.testing.expectError(error.LuaError, lua.doString("for i = 1, 3 do counter:missing() end", .{ .name = "=unit" }));
    const message = try @import("api_expect.zig").describeError(lua, error.LuaError);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "attempt to call a nil value (method 'missing')") != null);
}
