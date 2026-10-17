const std = @import("std");
const api = @import("../api.zig");
const Context = api.Context;
const Function = api.Function;
const State = api.State;
const Table = api.Table;
const Tuple = api.Tuple;
const Value = api.Value;

const memory_limit_error_message = "memory limit exceeded";

test "api host callbacks read arguments and return multiple values" {
    const Callbacks = struct {
        fn add(ctx: *Context) !void {
            const lhs = try ctx.arg(0, i64);
            const rhs = try ctx.arg(1, i64);
            try ctx.returnValues(.{ lhs + rhs, "ok" });
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host_add = try lua.register("host_add", Callbacks.add);
    defer host_add.deinit();

    try std.testing.expectError(error.TypeMismatch, lua.getGlobal("host_add", Function));

    const Result = Tuple(&.{ i64, []const u8 });
    var result = try host_add.call(.{ 20, 22 }, Result);
    defer result.deinit();

    try std.testing.expectEqual(@as(i64, 42), result.get(0));
    try std.testing.expectEqualStrings("ok", result.get(1));
}

test "api host callback functions can be installed as globals" {
    const Callbacks = struct {
        fn add(ctx: *Context) !void {
            const lhs = try ctx.arg(0, i64);
            const rhs = try ctx.arg(1, i64);
            try ctx.returnValues(.{ lhs + rhs, "ok" });
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host_add = try lua.register("host_add", Callbacks.add);
    defer host_add.deinit();
    try lua.setGlobal("host_add", host_add);
    try lua.doString(
        \\local sum, label = host_add(20, 22)
        \\assert(sum == 42)
        \\assert(label == 'ok')
    , .{ .name = "=api-21.4-host-add" });
}

test "api host callback argument errors become Lua errors" {
    const Callbacks = struct {
        fn needInteger(ctx: *Context) !void {
            _ = try ctx.arg(0, i64);
            try ctx.returnValues(.{});
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var need_integer = try lua.register("need_integer", Callbacks.needInteger);
    defer need_integer.deinit();
    try lua.setGlobal("need_integer", need_integer);
    var chunk = try lua.loadString("return need_integer('nope')", .{ .name = "=api-21.4-arg-error" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "need_integer") != null);
            try std.testing.expect(std.mem.indexOf(u8, message, "number") != null);
        },
    }
}

test "api host callback can raise Lua error values" {
    const Callbacks = struct {
        fn fail(ctx: *Context) !void {
            return ctx.raise("host boom");
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host_fail = try lua.register("host_fail", Callbacks.fail);
    defer host_fail.deinit();
    try lua.setGlobal("host_fail", host_fail);
    var chunk = try lua.loadString("host_fail()", .{ .name = "=api-21.4-raise" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "host boom") != null);
        },
    }
}

test "api memory limit applies to host callback return conversion" {
    const Callbacks = struct {
        const payload: [512 * 1024]u8 = @splat('x');

        fn large(ctx: *Context) !void {
            try ctx.returnValues(payload[0..]);
        }
    };

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .base,
        .limits = .{ .max_memory = 128 * 1024 },
    });
    defer lua.deinit();

    var large = try lua.register("large", Callbacks.large);
    defer large.deinit();
    try lua.setGlobal("large", large);
    var chunk = try lua.loadString("return large()", .{ .name = "=api-memory-callback-limit" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, memory_limit_error_message) != null);
        },
    }
}

test "api host callback can hold and call Lua callback function" {
    const Callbacks = struct {
        fn each(ctx: *Context) !void {
            var callback = try ctx.arg(0, Function);
            defer callback.deinit();

            const first = try callback.call(.{20}, i64);
            const second = try callback.call(.{41}, i64);
            try ctx.returnValues(.{ first, second });
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host_each = try lua.register("host_each", Callbacks.each);
    defer host_each.deinit();
    try lua.setGlobal("host_each", host_each);
    try lua.doString(
        \\local a, b = host_each(function(value)
        \\  return value + 1
        \\end)
        \\assert(a == 21)
        \\assert(b == 42)
    , .{ .name = "=api-21.4-lua-callback" });
}

test "api typed host callback wrapper compiles and runs" {
    const Callbacks = struct {
        fn clamp(value: f64, min: f64, max: f64) f64 {
            return @min(@max(value, min), max);
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var clamp = try lua.registerTyped("clamp", Callbacks.clamp);
    defer clamp.deinit();
    try lua.setGlobal("clamp", clamp);
    try lua.doString(
        \\assert(clamp(5, 1, 10) == 5)
        \\assert(clamp(-1, 1, 10) == 1)
        \\assert(clamp(11, 1, 10) == 10)
    , .{ .name = "=api-21.4-typed" });
}

test "host registration is native and does not compile or execute Lua" {
    const Callbacks = struct {
        fn echo(ctx: *Context) !void {
            try std.testing.expectEqual(@as(usize, 3), ctx.argCount());
            try ctx.returnValues(.{ try ctx.arg(0, i64), try ctx.arg(1, ?i64), try ctx.arg(2, []const u8) });
        }
    };
    var lua = try State.init(std.testing.allocator, .{ .stdlib = .none });
    defer lua.deinit();
    var first = try lua.register("echo", Callbacks.echo);
    defer first.deinit();
    var second = try lua.register("echo", Callbacks.echo);
    defer second.deinit();
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.proto_allocations.items.len);
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.closure_allocations.items.len);
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.source_allocations.items.len);
    try std.testing.expect(lua.raw_state.getGlobal("__zlua_api_callback") == .nil);
    try std.testing.expectError(error.TypeMismatch, first.dumpBytecode(.{}));
    try lua.setGlobal("first", first);
    try lua.setGlobal("second", second);
    const Result = Tuple(&.{ i64, ?i64, []const u8 });
    var result = try first.call(.{ 42, null, "last" }, Result);
    defer result.deinit();
    try std.testing.expectEqual(@as(i64, 42), result.get(0));
    try std.testing.expectEqual(@as(?i64, null), result.get(1));
    try std.testing.expectEqualStrings("last", result.get(2));
    try lua.openLibs(.full);
    try lua.doString(
        \\assert(type(first) == 'function' and first ~= second)
        \\assert(string.format("%p", first) ~= string.format("%p", second))
        \\local t = {[first] = 'first', [second] = 'second'}
        \\assert(t[first] == 'first' and t[second] == 'second')
        \\local info = debug.getinfo(first, 'Su')
        \\assert(info.what == 'C' and info.nups == 0 and info.isvararg)
        \\assert(debug.getupvalue(first, 1) == nil)
        \\assert(not pcall(string.dump, first))
        \\__zlua_api_callback = function() error('must not be used') end
        \\collectgarbage()
        \\local ok, a, b, c = pcall(first, 42, nil, 'last')
        \\assert(ok and a == 42 and b == nil and c == 'last')
        \\local co = coroutine.create(first)
        \\ok, a, b, c = coroutine.resume(co, 42, nil, 'last')
        \\assert(ok and a == 42 and b == nil and c == 'last')
        \\local calls, returns = 0, 0
        \\debug.sethook(function(event)
        \\  if debug.getinfo(2, 'f').func == first then
        \\    if event == 'call' then calls = calls + 1 end
        \\    if event == 'return' then returns = returns + 1 end
        \\  end
        \\end, 'cr')
        \\first(42, nil, 'last')
        \\debug.sethook()
        \\assert(calls == 1 and returns == 1)
    , .{});
}

test "native callback handles roundtrip and protect direct errors" {
    const Callbacks = struct {
        fn fail(ctx: *Context) !void {
            try std.testing.expectEqual(@as(usize, 0), ctx.argCount());
            return ctx.raise("native failure");
        }
    };
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var function = try lua.register("fail", Callbacks.fail);
    defer function.deinit();
    try lua.setGlobal("fail", function);
    var value = try lua.getGlobal("fail", Value);
    defer value.deinit();
    try lua.setGlobal("alias", value);
    var alias = try lua.getGlobal("alias", Function);
    defer alias.deinit();
    try std.testing.expectError(error.LuaError, alias.call(.{}, void));
    const result = try alias.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expectEqualStrings("native failure", message);
        },
    }
}

test "native callback registration rolls back on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn check(allocator: std.mem.Allocator) !void {
            var lua = try State.init(allocator, .{ .stdlib = .none });
            defer lua.deinit();
            var function = lua.registerTyped("identity", identity) catch |err| {
                try std.testing.expectEqual(@as(usize, 0), lua.callbacks.items.len);
                try std.testing.expectEqual(@as(usize, 0), lua.raw_state.activeRootCount());
                return err;
            };
            defer function.deinit();
            try std.testing.expectEqual(@as(i64, 42), try function.call(.{42}, i64));
        }
        fn identity(value: i64) i64 {
            return value;
        }
    }.check, .{});
}

test "native callback arguments and pending returns survive reentrant collection" {
    const Callbacks = struct {
        fn collect(ctx: *Context) !void {
            try ctx.state().doString("collectgarbage(); collectgarbage()", .{});
        }
        fn retain(ctx: *Context) !void {
            try ctx.state().doString("inner(); assert(weak.argument ~= nil)", .{});
            var argument = try ctx.arg(0, Table);
            defer argument.deinit();
            try std.testing.expectEqual(@as(i64, 42), try argument.get("value", i64));
            var weak = try ctx.state().getGlobal("weak", Table);
            defer weak.deinit();
            {
                var result = try ctx.state().createTable(.{});
                defer result.deinit();
                try result.set("value", @as(i64, 99));
                try weak.set("result", result);
                try ctx.pushReturn(result);
            }
            try ctx.state().doString("inner(); assert(weak.result ~= nil)", .{});
        }
    };
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var retain = try lua.register("retain", Callbacks.retain);
    defer retain.deinit();
    var inner = try lua.register("inner", Callbacks.collect);
    defer inner.deinit();
    try lua.setGlobal("retain", retain);
    try lua.setGlobal("inner", inner);
    try lua.doString(
        \\weak = setmetatable({}, {__mode = 'v'})
        \\local result = retain((function()
        \\  local argument = {value = 42}
        \\  weak.argument = argument
        \\  return argument
        \\end)())
        \\assert(result.value == 99)
    , .{});
}

test "native callbacks work as library callbacks and iterators" {
    const Callbacks = struct {
        fn twice(value: []const u8) !i64 {
            return 2 * try std.fmt.parseInt(i64, value, 10);
        }
        fn reader(ctx: *Context) !void {
            if (try ctx.state().getGlobal("read_done", ?bool) orelse false) return;
            try ctx.state().setGlobal("read_done", true);
            try ctx.returnValues("return 42");
        }
        fn next(limit: i64, previous: ?i64) ?i64 {
            const value = (previous orelse 0) + 1;
            return if (value <= limit) value else null;
        }
    };
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var twice = try lua.registerTyped("twice", Callbacks.twice);
    defer twice.deinit();
    var reader = try lua.register("reader", Callbacks.reader);
    defer reader.deinit();
    var next = try lua.registerTyped("iterator", Callbacks.next);
    defer next.deinit();
    try lua.setGlobal("twice", twice);
    try lua.setGlobal("reader", reader);
    try lua.setGlobal("iterator", next);
    try lua.doString(
        \\assert(string.gsub('1 2 3', '%d', twice) == '2 4 6')
        \\assert(assert(load(reader))() == 42)
        \\local sum = 0
        \\for i in iterator, 3 do sum = sum + i end
        \\assert(sum == 6)
    , .{});
}
