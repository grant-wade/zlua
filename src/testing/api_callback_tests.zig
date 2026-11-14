const std = @import("std");
const api = @import("../api.zig");
const dumpBytecode = @import("api_expect.zig").dumpBytecode;
const describeError = @import("api_expect.zig").describeError;
const errorMessage = @import("api_expect.zig").errorMessage;
const callError = @import("api_expect.zig").callError;
const expectString = @import("api_expect.zig").expectString;
const Context = api.Context;
const Function = api.Function;
const State = api.State;
const Table = api.Table;
const Value = api.Value;

const memory_limit_error_message = "memory limit exceeded";

fn expectProtectedErrorContains(lua: *State, function: Function, needle: []const u8) !void {
    var err = try callError(function, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    if (std.mem.indexOf(u8, message, needle) == null) {
        std.debug.print("expected \"{s}\" in \"{s}\"\n", .{ needle, message });
        return error.TestUnexpectedMessage;
    }
}

test "api host callbacks read arguments and return multiple values" {
    const Callbacks = struct {
        fn add(ctx: *Context) !void {
            const lhs = try ctx.arg(0, i64);
            const rhs = try ctx.arg(1, i64);
            try ctx.returnValues(.{ lhs + rhs, "ok" });
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host_add = try lua.newFunction("host_add", Callbacks.add);
    defer host_add.deinit();

    try std.testing.expectError(error.TypeMismatch, lua.getGlobal("host_add", Function));

    const Result = struct { i64, api.String };
    var result = try host_add.call(.{ 20, 22 }, Result);
    defer api.deinit(&result);

    try std.testing.expectEqual(@as(i64, 42), result[0]);
    try std.testing.expectEqualStrings("ok", try result[1].bytes());
}

test "api host callback functions can be installed as globals" {
    const Callbacks = struct {
        fn add(ctx: *Context) !void {
            const lhs = try ctx.arg(0, i64);
            const rhs = try ctx.arg(1, i64);
            try ctx.returnValues(.{ lhs + rhs, "ok" });
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host_add = try lua.newFunction("host_add", Callbacks.add);
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var need_integer = try lua.newFunction("need_integer", Callbacks.needInteger);
    defer need_integer.deinit();
    try lua.setGlobal("need_integer", need_integer);
    var chunk = try lua.loadString("return need_integer('nope')", .{ .name = "=api-21.4-arg-error" });
    defer chunk.deinit();

    var err = try callError(chunk, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "need_integer") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "number") != null);
}

test "api host callback can raise Lua error values" {
    const Callbacks = struct {
        fn fail(ctx: *Context) !void {
            return ctx.raise("host boom");
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host_fail = try lua.newFunction("host_fail", Callbacks.fail);
    defer host_fail.deinit();
    try lua.setGlobal("host_fail", host_fail);
    var chunk = try lua.loadString("host_fail()", .{ .name = "=api-21.4-raise" });
    defer chunk.deinit();

    var err = try callError(chunk, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "host boom") != null);
}

test "api memory limit applies to host callback return conversion" {
    const Callbacks = struct {
        const payload: [512 * 1024]u8 = @splat('x');

        fn large(ctx: *Context) !void {
            try ctx.returnValues(payload[0..]);
        }
    };

    const lua = try State.init(std.testing.allocator, .{
        .stdlib = .base,
        .limits = .{ .max_memory = 128 * 1024 },
    });
    defer lua.deinit();

    var large = try lua.newFunction("large", Callbacks.large);
    defer large.deinit();
    try lua.setGlobal("large", large);
    var chunk = try lua.loadString("return large()", .{ .name = "=api-memory-callback-limit" });
    defer chunk.deinit();

    var err = try callError(chunk, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, memory_limit_error_message) != null);
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host_each = try lua.newFunction("host_each", Callbacks.each);
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

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var clamp = try lua.newTypedFunction("clamp", Callbacks.clamp);
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
    const lua = try State.init(std.testing.allocator, .{ .stdlib = .none });
    defer lua.deinit();
    var first = try lua.newFunction("echo", Callbacks.echo);
    defer first.deinit();
    var second = try lua.newFunction("echo", Callbacks.echo);
    defer second.deinit();
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.chunk_allocations.items.len);
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.closure_allocations.items.len);
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.source_allocations.items.len);
    try std.testing.expect(lua.raw_state.getGlobal("__zlua_api_callback") == .nil);
    try std.testing.expectError(error.TypeMismatch, dumpBytecode(first, .{}));
    try lua.setGlobal("first", first);
    try lua.setGlobal("second", second);
    const Result = struct { i64, ?i64, api.String };
    var result = try first.call(.{ 42, null, "last" }, Result);
    defer api.deinit(&result);
    try std.testing.expectEqual(@as(i64, 42), result[0]);
    try std.testing.expectEqual(@as(?i64, null), result[1]);
    try std.testing.expectEqualStrings("last", try result[2].bytes());
    try lua.openLibs(.full);
    try lua.doString(
        \\assert(type(first) == 'function' and first == second)
        \\assert(string.format("%p", first) == string.format("%p", second))
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
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var function = try lua.newFunction("fail", Callbacks.fail);
    defer function.deinit();
    try lua.setGlobal("fail", function);
    var value = try lua.getGlobal("fail", Value);
    defer value.deinit();
    try lua.setGlobal("alias", value);
    var alias = try lua.getGlobal("alias", Function);
    defer alias.deinit();
    try std.testing.expectError(error.LuaError, alias.call(.{}, void));
    var err = try callError(alias, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expectEqualStrings("native failure", message);
}

test "native callback registration rolls back on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn check(allocator: std.mem.Allocator) !void {
            const lua = try State.init(allocator, .{ .stdlib = .none });
            defer lua.deinit();
            var function = lua.newTypedFunction("identity", identity) catch |err| {
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
                var result = try ctx.state().newTable(.{});
                defer result.deinit();
                try result.set("value", @as(i64, 99));
                try weak.set("result", result);
                try ctx.pushReturn(result);
            }
            try ctx.state().doString("inner(); assert(weak.result ~= nil)", .{});
        }
    };
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var retain = try lua.newFunction("retain", Callbacks.retain);
    defer retain.deinit();
    var inner = try lua.newFunction("inner", Callbacks.collect);
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
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var twice = try lua.newTypedFunction("twice", Callbacks.twice);
    defer twice.deinit();
    var reader = try lua.newFunction("reader", Callbacks.reader);
    defer reader.deinit();
    var next = try lua.newTypedFunction("iterator", Callbacks.next);
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

const IoCallbacks = struct {
    var dir: std.Io.Dir = undefined;

    fn hasIo(ctx: *Context) !void {
        try ctx.returnValues(.{ctx.io() != null});
    }

    fn hasIoTyped(ctx: *Context) bool {
        return ctx.io() != null;
    }

    fn matchesTestingIo(ctx: *Context) !void {
        const io = ctx.io() orelse return ctx.raise("host I/O is not configured");
        try ctx.returnValues(.{io.vtable == std.testing.io.vtable});
    }

    fn readFile(ctx: *Context) !void {
        const io = ctx.io() orelse return ctx.raise("host I/O is not configured");
        const path = try ctx.arg(0, []const u8);
        const allocator = ctx.state().allocator();
        const bytes = dir.readFileAlloc(io, path, allocator, .limited(1024)) catch |err| return ctx.raise(@errorName(err));
        defer allocator.free(bytes);
        try ctx.returnValues(.{bytes});
    }
};

fn installIoCallbacks(lua: *State) !void {
    var has_io = try lua.newFunction("has_io", IoCallbacks.hasIo);
    defer has_io.deinit();
    try lua.setGlobal("has_io", has_io);
    var has_io_typed = try lua.newTypedFunction("has_io_typed", IoCallbacks.hasIoTyped);
    defer has_io_typed.deinit();
    try lua.setGlobal("has_io_typed", has_io_typed);
    var matches_testing_io = try lua.newFunction("matches_testing_io", IoCallbacks.matchesTestingIo);
    defer matches_testing_io.deinit();
    try lua.setGlobal("matches_testing_io", matches_testing_io);
    var read_file = try lua.newFunction("read_file", IoCallbacks.readFile);
    defer read_file.deinit();
    try lua.setGlobal("read_file", read_file);
}

const expect_no_io =
    \\assert(has_io() == false)
    \\assert(has_io_typed() == false)
    \\local ok, err = pcall(read_file, "data.txt")
    \\assert(not ok and err == "host I/O is not configured")
;

const expect_testing_io =
    \\assert(has_io() == true)
    \\assert(has_io_typed() == true)
    \\assert(matches_testing_io() == true)
    \\assert(read_file("data.txt") == "from host")
;

test "api callback context io is null without configured io" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try installIoCallbacks(lua);
    try lua.doString(expect_no_io, .{ .name = "=no-io" });
}

test "api callback context io returns configured runtime io" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "data.txt", .data = "from host" });
    IoCallbacks.dir = temporary.dir;

    const lua = try State.init(std.testing.allocator, .{ .capabilities = .{ .io = .{ .runtime = std.testing.io } } });
    defer lua.deinit();
    try installIoCallbacks(lua);
    try lua.doString(expect_testing_io, .{ .name = "=io" });
}

test "api callback context io carries across snapshot states and reset" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "data.txt", .data = "from host" });
    IoCallbacks.dir = temporary.dir;

    const lua = try State.init(std.testing.allocator, .{ .capabilities = .{ .io = .{ .runtime = std.testing.io } } });
    defer lua.deinit();
    try installIoCallbacks(lua);
    var snapshot = try lua.snapshot(std.testing.allocator);
    defer snapshot.deinit();

    const first = try snapshot.newState(std.testing.allocator);
    defer first.deinit();
    const second = try snapshot.newState(std.testing.allocator);
    defer second.deinit();
    try first.doString(expect_testing_io, .{ .name = "=first" });
    try second.doString(expect_testing_io, .{ .name = "=second" });
    try first.reset();
    try first.doString(expect_testing_io, .{ .name = "=first-reset" });
}

test "api callback context io stays null across snapshot states and reset" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try installIoCallbacks(lua);
    var snapshot = try lua.snapshot(std.testing.allocator);
    defer snapshot.deinit();

    const worker = try snapshot.newState(std.testing.allocator);
    defer worker.deinit();
    try worker.doString(expect_no_io, .{ .name = "=worker" });
    try worker.reset();
    try worker.doString(expect_no_io, .{ .name = "=worker-reset" });
}

test "api function handles accept every callable lua value" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\return tostring, coroutine.wrap(function() return 1 end), ("a"):gmatch("a"), coroutine.yield
    , .{});
    defer chunk.deinit();
    var values = try chunk.call(.{}, struct { Function, Function, Function, api.Value });
    defer api.deinit(&values);

    try expectString("7", values[0].call(.{@as(i64, 7)}, api.String));
    try std.testing.expectEqual(@as(i64, 1), try values[1].call(.{}, i64));
    try expectString("a", values[2].call(.{}, api.String));
    try std.testing.expect(values[3] == .function);
}

test "api value type names match lua" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local names = {}
        \\for _, v in ipairs(...) do names[#names + 1] = type(v) end
        \\return names
    , .{});
    defer chunk.deinit();
    var source = try lua.loadString("return {true, 1, 1.5, 's', {}, print, coroutine.create(print)}", .{});
    defer source.deinit();
    var list = try source.call(.{}, Table);
    defer list.deinit();
    var expected = try chunk.call(.{list}, Table);
    defer expected.deinit();
    for (1..8) |index| {
        var value = try list.rawGet(@as(i64, @intCast(index)), api.Value);
        defer value.deinit();
        try expectString(value.typeName(), expected.rawGet(@as(i64, @intCast(index)), api.String));
    }
}

test "api integer arguments report numbers without an integer representation" {
    const Host = struct {
        fn takesInteger(ctx: *Context) !void {
            try ctx.returnValues(.{try ctx.arg(0, i64)});
        }

        fn takesOptional(ctx: *Context) !void {
            try ctx.returnValues(.{try ctx.optionalArg(0, i32)});
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var integer = try lua.newFunction("integer", Host.takesInteger);
    defer integer.deinit();
    try lua.setGlobal("integer", integer);
    var optional = try lua.newFunction("optional", Host.takesOptional);
    defer optional.deinit();
    try lua.setGlobal("optional", optional);

    var fraction = try lua.loadString("return integer(1.5)", .{});
    defer fraction.deinit();
    try expectProtectedErrorContains(lua, fraction, "bad argument #1 to 'integer' (number has no integer representation)");
    var optional_fraction = try lua.loadString("return optional(1.5)", .{});
    defer optional_fraction.deinit();
    try expectProtectedErrorContains(lua, optional_fraction, "number has no integer representation");
    var too_large = try lua.loadString("return integer(2^63)", .{});
    defer too_large.deinit();
    try expectProtectedErrorContains(lua, too_large, "number has no integer representation");
    var text = try lua.loadString("return integer('x')", .{});
    defer text.deinit();
    try expectProtectedErrorContains(lua, text, "number expected, got string");
    var whole = try lua.loadString("return integer(2.0)", .{});
    defer whole.deinit();
    try std.testing.expectEqual(@as(i64, 2), try whole.call(.{}, i64));
}

test "api callbacks reach host data through the context and typed parameters" {
    const Game = struct {
        gold: i64,

        fn readGold(ctx: *Context) !void {
            const game = ctx.host(@This()) orelse return ctx.raise("no game");
            try ctx.returnValues(.{game.gold});
        }

        fn give(host: api.Host(@This()), amount: i64) i64 {
            host.ptr.gold += amount;
            return host.ptr.gold;
        }

        fn named(ctx: *Context) !void {
            try ctx.returnValues(.{ctx.functionName()});
        }
    };
    const Other = struct { unused: u8 };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var game = Game{ .gold = 5 };

    var gold = try lua.newFunction("gold", Game.readGold);
    defer gold.deinit();
    try lua.setGlobal("gold", gold);
    var give = try lua.newTypedFunction("give", Game.give);
    defer give.deinit();
    try lua.setGlobal("give", give);
    var named = try lua.newFunction("the_name", Game.named);
    defer named.deinit();
    try lua.setGlobal("named", named);

    var unset = try lua.loadString("return give(1)", .{});
    defer unset.deinit();
    try expectProtectedErrorContains(lua, unset, "no host");

    try lua.setHost(&game);
    try std.testing.expect(lua.host(Other) == null);
    try std.testing.expectEqual(&game, lua.host(Game).?);
    try lua.doString(
        \\assert(gold() == 5)
        \\assert(give(3) == 8)
        \\assert(give(2) == 10)
        \\assert(named() == "the_name")
    , .{});
    try std.testing.expectEqual(@as(i64, 10), game.gold);

    try lua.clearHost();
    try std.testing.expect(lua.host(Game) == null);
}

test "api host data follows snapshots and reset" {
    const Game = struct {
        id: i64,

        fn readId(host: api.Host(@This())) i64 {
            return host.ptr.id;
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var original = Game{ .id = 1 };
    var replacement = Game{ .id = 2 };
    try lua.setHost(&original);
    var id = try lua.newTypedFunction("id", Game.readId);
    try lua.setGlobal("id", id);
    id.deinit();

    var snapshot = try lua.snapshot(std.testing.allocator);
    defer snapshot.deinit();
    const worker = try snapshot.newState(std.testing.allocator);
    defer worker.deinit();
    try worker.doString("assert(id() == 1)", .{});
    try worker.setHost(&replacement);
    try worker.doString("assert(id() == 2)", .{});
    try worker.reset();
    try worker.doString("assert(id() == 1)", .{});
    try std.testing.expectEqual(&original, lua.host(Game).?);
}

test "api raisef prefixes the lua position and argError names the argument" {
    const Host = struct {
        fn fail(ctx: *Context) !void {
            return ctx.raisef("bad value {d}", .{try ctx.arg(0, i64)});
        }

        fn badArgument(ctx: *Context) !void {
            return ctx.argError(1, "not a color");
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var fail = try lua.newFunction("fail", Host.fail);
    defer fail.deinit();
    try lua.setGlobal("fail", fail);
    var bad = try lua.newFunction("bad", Host.badArgument);
    defer bad.deinit();
    try lua.setGlobal("bad", bad);

    var chunk = try lua.loadString("\nfail(7)", .{ .name = "@scripts/thing.lua" });
    defer chunk.deinit();
    try expectProtectedErrorContains(lua, chunk, "scripts/thing.lua:2: bad value 7");

    var long = try lua.loadString("fail(1)", .{ .name = "@a/long/directory/path/that/does/not/fit/in/a/chunk/id/at/all/end.lua" });
    defer long.deinit();
    try expectProtectedErrorContains(lua, long, "...");
    try expectProtectedErrorContains(lua, long, "end.lua:1: bad value 1");

    var err = try callError(fail, .{@as(i64, 3)}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expectEqualStrings("bad value 3", message);

    var argument = try lua.loadString("bad(1, 2)", .{});
    defer argument.deinit();
    try expectProtectedErrorContains(lua, argument, "bad argument #2 to 'bad' (not a color)");
}

test "api caller walks the lua functions of a coroutine" {
    const Host = struct {
        var sources: [3][64]u8 = undefined;
        var lines: [3]?usize = undefined;
        var count: usize = 0;

        fn record(ctx: *Context) !void {
            count = 0;
            while (ctx.caller(count)) |at| : (count += 1) {
                if (count == sources.len) return error.TestTooManyCallers;
                @memcpy(sources[count][0..at.source.len], at.source);
                sources[count][at.source.len] = 0;
                lines[count] = at.line;
            }
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var record = try lua.newFunction("record", Host.record);
    defer record.deinit();
    try lua.setGlobal("record", record);

    try record.call(.{}, void);
    try std.testing.expectEqual(@as(usize, 0), Host.count);

    var chunk = try lua.loadString(
        \\local function inner()
        \\  record()
        \\end
        \\pcall(inner)
    , .{ .name = "@walk.lua" });
    defer chunk.deinit();
    try chunk.call(.{}, void);
    try std.testing.expectEqual(@as(usize, 2), Host.count);
    try std.testing.expectEqualStrings("@walk.lua", std.mem.sliceTo(&Host.sources[0], 0));
    try std.testing.expectEqual(@as(?usize, 2), Host.lines[0]);
    try std.testing.expectEqual(@as(?usize, 4), Host.lines[1]);

    var in_coroutine = try lua.loadString("\n\nrecord()", .{ .name = "=co" });
    defer in_coroutine.deinit();
    var co = try lua.newCoroutine(in_coroutine);
    defer co.deinit();
    var resumed = try co.resumeCoroutine(.{}, void, void);
    resumed.deinit();
    try std.testing.expectEqual(@as(usize, 1), Host.count);
    try std.testing.expectEqualStrings("=co", std.mem.sliceTo(&Host.sources[0], 0));
    try std.testing.expectEqual(@as(?usize, 3), Host.lines[0]);

    const stripped_bytes = try dumpBytecode(chunk, .{ .strip_debug = true });
    defer lua.allocator().free(stripped_bytes);
    var stripped = try lua.loadBytecode(stripped_bytes, .{});
    defer stripped.deinit();
    try stripped.call(.{}, void);
    try std.testing.expectEqual(@as(?usize, null), Host.lines[0]);
}

test "api describeError gives the lua message or the error name" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString("return setmetatable({}, { __index = function() error('boom', 0) end })", .{});
    defer chunk.deinit();
    var table = try chunk.call(.{}, Table);
    defer table.deinit();
    const failure = if (table.get("x", Value)) |_| error.TestExpectedLuaError else |err| err;
    const message = try describeError(lua, failure);
    defer lua.allocator().free(message);
    try std.testing.expectEqualStrings("boom", message);

    const name = try describeError(lua, error.TypeMismatch);
    defer lua.allocator().free(name);
    try std.testing.expectEqualStrings("TypeMismatch", name);
}

const LineCallbacks = struct {
    fn currentLine(ctx: *Context) !void {
        try ctx.returnValues(.{ctx.currentLine()});
    }

    fn currentLineTyped(ctx: *Context) ?usize {
        return ctx.currentLine();
    }

    fn callThrough(ctx: *Context) !void {
        var function = try ctx.arg(0, Function);
        defer function.deinit();
        const line = try ctx.callNonYielding(function, .{}, ?i64);
        try ctx.returnValues(.{line});
    }
};

fn installLineCallbacks(lua: *State) !void {
    var line = try lua.newFunction("line", LineCallbacks.currentLine);
    defer line.deinit();
    try lua.setGlobal("line", line);
    var line_typed = try lua.newTypedFunction("line_typed", LineCallbacks.currentLineTyped);
    defer line_typed.deinit();
    try lua.setGlobal("line_typed", line_typed);
    var call_through = try lua.newFunction("call_through", LineCallbacks.callThrough);
    defer call_through.deinit();
    try lua.setGlobal("call_through", call_through);
}

test "api callback context currentLine reports the calling Lua line" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try installLineCallbacks(lua);
    try lua.doString(
        \\assert(line() == 1)
        \\
        \\assert(line_typed() == 3)
        \\local function nested()
        \\  return (line())
        \\end
        \\assert(nested() == 5)
        \\local function tail() return line() end
        \\assert(tail() == 8)
        \\local ok, value = pcall(line)
        \\assert(ok and value == 10)
        \\ok, value = xpcall(line, print)
        \\assert(ok and value == 12)
    , .{ .name = "=line-calls" });
}

test "api callback context currentLine tracks each line within a function" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try installLineCallbacks(lua);
    try lua.doString(
        \\local seen = {}
        \\for i = 1, 3 do
        \\  seen[#seen + 1] = line()
        \\  local x = i * 2
        \\  seen[#seen + 1] = line() + x - x
        \\end
        \\assert(table.concat(seen, ",") == "3,5,3,5,3,5")
    , .{ .name = "=line-loop" });
}

test "api callback context currentLine works from metamethods and iterators" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try installLineCallbacks(lua);
    try lua.doString(
        \\local t = setmetatable({}, { __index = line, __add = line, __call = line })
        \\local a = t.x
        \\local b = t + 1
        \\local c = t()
        \\assert(a == 2 and b == 3 and c == 4)
        \\local seen
        \\for v in line do
        \\  seen = v
        \\  break
        \\end
        \\assert(seen == 7)
    , .{ .name = "=line-meta" });
}

test "api callback context currentLine follows the running coroutine" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try installLineCallbacks(lua);
    try lua.doString(
        \\local co = coroutine.wrap(function()
        \\  coroutine.yield(line())
        \\  return line()
        \\end)
        \\assert(co() == 2)
        \\assert(line() == 6)
        \\assert(co() == 3)
    , .{ .name = "=line-coroutine" });
}

test "api callback context currentLine is null without a Lua frame" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try installLineCallbacks(lua);

    var line = try lua.getGlobal("line", Function);
    defer line.deinit();
    try std.testing.expectEqual(@as(?i64, null), try line.call(.{}, ?i64));

    try lua.doString(
        \\assert(coroutine.wrap(line)() == nil)
    , .{ .name = "=line-no-frame" });
}

test "api callback context currentLine reports the nearest Lua frame through nested callbacks" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try installLineCallbacks(lua);
    try lua.doString(
        \\local function inner()
        \\  return (line())
        \\end
        \\assert(call_through(inner) == 2)
        \\assert(call_through(line) == 5)
    , .{ .name = "=line-nested" });
}

test "api callback context currentLine is null for stripped functions" {
    const lua = try State.init(std.testing.allocator, .{ .binary_chunks = true });
    defer lua.deinit();
    try installLineCallbacks(lua);
    try lua.doString(
        \\local function f() return (line()) end
        \\assert(f() == 1)
        \\local stripped = load(string.dump(f, true), "stripped", "b")
        \\assert(stripped() == nil)
    , .{ .name = "=line-stripped" });
}

fn liveRoots(lua: *State) usize {
    var count: usize = 0;
    for (lua.raw_state.api_roots.items) |root| {
        if (root != .nil) count += 1;
    }
    return count;
}

test "api typed callbacks release handle parameters" {
    const Host = struct {
        var kept: ?Function = null;

        fn size(table: Table, value: Value, function: ?Function) !i64 {
            _ = value;
            _ = function;
            return table.rawLen();
        }

        fn same(table: Table) Table {
            return table;
        }

        fn keep(ctx: *Context, value: Value) !void {
            kept = try ctx.state().read(value, Function);
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var size = try lua.newTypedFunction("size", Host.size);
    defer size.deinit();
    try lua.setGlobal("size", size);
    var same = try lua.newTypedFunction("same", Host.same);
    defer same.deinit();
    try lua.setGlobal("same", same);
    var keep = try lua.newTypedFunction("keep", Host.keep);
    defer keep.deinit();
    try lua.setGlobal("keep", keep);

    const before = liveRoots(lua);
    try lua.doString(
        \\local t = { 1, 2 }
        \\for _ = 1, 100 do
        \\  assert(size(t, {}, print) == 2)
        \\  assert(size(t, "x") == 2)
        \\  assert(same(t) == t)
        \\  assert(not pcall(size, t, {}, 1))
        \\  assert(not pcall(size, 1))
        \\end
        \\keep(function() return 7 end)
    , .{});
    collectLast: {
        var kept = Host.kept orelse break :collectLast;
        defer kept.deinit();
        try lua.collect();
        try std.testing.expectEqual(@as(i64, 7), try kept.call(.{}, i64));
    }
    Host.kept = null;
    try std.testing.expectEqual(before, liveRoots(lua));
}

test "api handle scopes release handles and keep what they are told to" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    const before = liveRoots(lua);

    var outer = try lua.newTable(.{});
    defer outer.deinit();
    const kept = blk: {
        var scope = lua.handleScope();
        defer scope.end();
        var a = try lua.newTable(.{});
        var dropped = try lua.newTable(.{});
        dropped.deinit();
        var reused = try lua.newTable(.{});
        try reused.rawSet("n", 1);
        try a.rawSet("reused", reused);
        var value = try a.rawGet("reused", Value);
        _ = &value;
        {
            var inner = lua.handleScope();
            defer inner.end();
            _ = try lua.newTable(.{});
            _ = try lua.newTable(.{});
            outer.deinit();
            outer = try lua.newTable(.{});
            try std.testing.expectEqual(before + 6, liveRoots(lua));
            outer = inner.keep(outer);
        }
        try std.testing.expectEqual(before + 4, liveRoots(lua));
        break :blk scope.keep(a);
    };
    try std.testing.expectEqual(before + 2, liveRoots(lua));
    var table = kept;
    defer table.deinit();
    var reused = try table.rawGet("reused", Table);
    defer reused.deinit();
    try std.testing.expectEqual(@as(i64, 1), try reused.rawGet("n", i64));
}

test "api handle scopes leave roots outside handles alone" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var t = try lua.newTable(.{});
    defer t.deinit();
    try t.rawSet("a", 1);
    try t.rawSet("b", 2);

    var scope = lua.handleScope();
    defer scope.end();
    var freed = try lua.newTable(.{});
    freed.deinit();
    var it = try t.rawIterator();
    defer it.deinit();
    var count: i64 = 0;
    while (try it.next()) |_| count += 1;
    try std.testing.expectEqual(@as(i64, 2), count);
    for (0..1000) |_| {
        var loop = try lua.newTable(.{});
        loop.deinit();
    }
    try std.testing.expect(lua.scoped_roots.items.len < 16);
}

test "api handle scopes end quietly after a reset" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var snapshot = try lua.snapshot(std.testing.allocator);
    defer snapshot.deinit();
    {
        var scope = lua.handleScope();
        defer scope.end();
        _ = try lua.newTable(.{});
        try lua.reset();
        try std.testing.expectEqual(@as(usize, 0), lua.open_handle_scopes);
    }
    var scope = lua.handleScope();
    defer scope.end();
    _ = try lua.newTable(.{});
    try std.testing.expectEqual(@as(usize, 1), lua.scoped_roots.items.len);
}

test "registering a callback again reuses its entry" {
    const Counter = struct {
        value: i64 = 0,

        pub fn inc(self: *@This()) void {
            self.value += 1;
        }
    };
    const Callbacks = struct {
        fn noop(_: *Context) !void {}
    };
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var metatable = try lua.newTable(.{});
    defer metatable.deinit();

    var first = try lua.newFunction("noop", Callbacks.noop);
    defer first.deinit();
    var counter = try lua.newUserdata(Counter, .{}, .{ .metatable = metatable });
    counter.deinit();
    const entries = lua.callbacks.items.len;

    for (0..100) |_| {
        var again = try lua.newFunction("noop", Callbacks.noop);
        again.deinit();
        var another = try lua.newUserdata(Counter, .{}, .{ .metatable = metatable });
        another.deinit();
    }
    try std.testing.expectEqual(entries, lua.callbacks.items.len);

    var renamed = try lua.newFunction("other", Callbacks.noop);
    defer renamed.deinit();
    try std.testing.expectEqual(entries + 1, lua.callbacks.items.len);
}

test "typed callbacks release handles returned in a tuple" {
    const Callbacks = struct {
        fn pair(ctx: *Context) !struct { Table, api.String } {
            var table = try ctx.state().newTable(.{});
            errdefer table.deinit();
            try ctx.state().doString("last = 'pair'", .{});
            return .{ table, try ctx.state().getGlobal("last", api.String) };
        }
    };
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try lua.setGlobal("pair", Callbacks.pair);
    const roots = lua.raw_state.activeRootCount();
    try lua.doString("local t, s = pair() assert(type(t) == 'table' and s == 'pair')", .{});
    try std.testing.expectEqual(roots, lua.raw_state.activeRootCount());
}
