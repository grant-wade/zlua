const std = @import("std");
const api = @import("../api.zig");
const expectString = @import("api_expect.zig").expectString;
const a = std.testing.allocator;

fn add(x: i64, y: i64) i64 {
    return x + y;
}

fn clamp(value: i64, min: i64, max: i64) i64 {
    return @min(@max(value, min), max);
}

fn named(ctx: *api.Context) !void {
    try ctx.returnValues(.{ctx.functionName()});
}

const Wallet = struct {
    gold: i64,

    fn give(host: api.Host(Wallet), amount: i64) i64 {
        host.ptr.gold += amount;
        return host.ptr.gold;
    }
};

const Elsewhere = struct {
    pub fn far() i64 {
        return 1;
    }
};

const Api = struct {
    pub const version = "1.2.0";
    pub const max_players = 8;
    pub var counter: i64 = 0;
    pub const ratio = 0.5;
    pub const mode = .strict;

    pub fn add(x: i64, y: i64) i64 {
        return x + y;
    }

    pub fn bump() i64 {
        counter += 1;
        return counter;
    }

    pub const math = struct {
        pub fn double(x: i64) i64 {
            return x * 2;
        }

        pub const nested = struct {
            pub const depth = 2;
        };
    };

    pub const Kind = enum {
        sword,
        spear,

        pub fn reach(kind: Kind) i64 {
            return switch (kind) {
                .sword => 1,
                .spear => 2,
            };
        }
    };
    pub const Point = struct { x: i64, y: i64 };
    pub const Self = @This();
    pub const borrowed = Elsewhere;
    pub const inventory = @import("globals_module_fixture.zig");
    pub const empty = struct {};
    pub const Opaque = opaque {};

    pub fn generic(value: anytype) @TypeOf(value) {
        return value;
    }

    pub fn hidden() void {}

    pub const lua = .{
        .add = .{ .key = "plus" },
        .generic = .{ .skip = true },
        .hidden = .{ .skip = true },
    };
};

test "setGlobals converts functions, values, and nested structs" {
    const lua = try api.State.init(a, .{});
    defer lua.deinit();

    var players: i64 = 4;
    players += 1;
    try lua.setGlobals(.{
        .add = add,
        .VERSION = "1.2.0",
        .players = players,
        .game = .{
            .clamp = clamp,
            .limits = .{ .max = 8 },
            .modes = .{ "easy", "hard" },
        },
    });

    try lua.doString(
        \\assert(add(20, 22) == 42)
        \\assert(VERSION == "1.2.0" and players == 5)
        \\assert(game.clamp(250, 0, 90) == 90)
        \\assert(game.limits.max == 8)
        \\assert(game.modes[1] == "easy" and game.modes[2] == "hard")
        \\assert(type(add) == "function" and type(game) == "table")
    , .{});
}

test "functions converted from Zig keep typed arguments and their errors" {
    const lua = try api.State.init(a, .{});
    defer lua.deinit();

    var wallet = Wallet{ .gold = 5 };
    try lua.setHost(&wallet);
    try lua.setGlobal("add", add);
    try lua.setGlobals(.{ .give = Wallet.give, .shop = .{ .named = named } });

    try lua.doString(
        \\assert(give(10) == 15)
        \\local ok, err = pcall(add, "x", 1)
        \\assert(not ok and err:find("bad argument #1 to 'add'", 1, true), err)
        \\ok, err = pcall(shop.named)
        \\assert(ok and err == "named", err)
    , .{});
    try std.testing.expectEqual(@as(i64, 15), wallet.gold);
}

test "a Zig function converts to one callback however often it is converted" {
    const lua = try api.State.init(a, .{});
    defer lua.deinit();

    try lua.setGlobal("add", add);
    const registered = lua.callbacks.items.len;
    for (0..10) |_| try lua.setGlobals(.{ .again = add, .math = .{ .add = add } });
    var t = try lua.newTable(.{});
    defer t.deinit();
    for (0..10) |_| try t.set("add", add);

    try std.testing.expectEqual(registered, lua.callbacks.items.len);
    try lua.doString("assert(add == again and add == math.add)", .{});
}

test "functions convert wherever Zig values go to Lua" {
    const lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();

    var t = try lua.newTable(.{});
    defer t.deinit();
    try t.set("add", add);
    try lua.setGlobal("t", t);
    try lua.setLoadedModule("calc", .{ .add = add, .clamp = clamp });

    try lua.doString(
        \\assert(t.add(1, 2) == 3)
        \\local calc = require("calc")
        \\assert(calc.add(2, 3) == 5 and calc.clamp(-5, 0, 10) == 0)
        \\function apply(f, x, y) return f(x, y) end
    , .{});

    var apply = try lua.getGlobal("apply", api.Function);
    defer apply.deinit();
    try std.testing.expectEqual(@as(i64, 9), try apply.call(.{ add, 4, 5 }, i64));
}

test "Table.setFields assigns through __newindex" {
    const lua = try api.State.init(a, .{});
    defer lua.deinit();

    try lua.doString(
        \\seen = {}
        \\target = setmetatable({}, { __newindex = function(t, k, v) seen[#seen + 1] = k; rawset(t, k, v) end })
    , .{});
    var target = try lua.getGlobal("target", api.Table);
    defer target.deinit();
    try target.setFields(.{ .add = add, .limit = 3 });

    try lua.doString(
        \\assert(#seen == 2 and target.add(1, 1) == 2 and target.limit == 3)
    , .{});
}

test "newTableFrom builds a sandboxed environment" {
    const lua = try api.State.init(a, .{});
    defer lua.deinit();

    var env = try lua.newTableFrom(.{ .add = add, .base = 10 });
    defer env.deinit();
    var chunk = try lua.loadString("return add(base, 5), print", .{ .name = "=env", .environment = env });
    defer chunk.deinit();

    var result = try chunk.call(.{}, struct { i64, ?api.Function });
    defer api.deinit(&result);
    try std.testing.expectEqual(@as(i64, 15), result[0]);
    try std.testing.expect(result[1] == null);
}

test "a struct type converts to a table of its exported public declarations" {
    const lua = try api.State.init(a, .{});
    defer lua.deinit();

    Api.counter = 40;
    try lua.setGlobal("api", Api);
    try lua.setGlobals(Api);

    try lua.doString(
        \\assert(api.version == "1.2.0" and api.max_players == 8 and api.ratio == 0.5)
        \\assert(api.mode == "strict" and api.counter == 40)
        \\assert(api.plus(2, 3) == 5 and api.add == nil)
        \\assert(api.bump() == 41 and api.bump() == 42 and api.counter == 40)
        \\assert(api.math.double(21) == 42 and api.math.nested.depth == 2)
        \\assert(api.Kind.sword == "sword" and api.Kind.spear == "spear")
        \\assert(api.Kind.reach(api.Kind.spear) == 2)
        \\assert(api.borrowed.far() == 1 and api.inventory.total({ 2, 3 }) == 5)
        \\for _, name in ipairs({ "Point", "Self", "empty", "Opaque", "generic", "hidden", "lua" }) do
        \\  assert(api[name] == nil, name)
        \\end
        \\assert(plus == api.plus and version == "1.2.0" and math.double(2) == 4)
    , .{});
    try std.testing.expectEqual(@as(i64, 42), Api.counter);

    var module = try lua.newTableFrom(Api.math);
    defer module.deinit();
    var nested = try module.get("nested", api.Table);
    defer nested.deinit();
    try std.testing.expectEqual(@as(i64, 2), try nested.get("depth", i64));

    var kinds = try lua.newTableFrom(Api.Kind);
    defer kinds.deinit();
    try expectString("sword", kinds.get("sword", api.String));
}

const Left = struct {
    pub const name = "left";
    pub const right = Right;
};

const Right = struct {
    pub const name = "right";
    pub const left = Left;
};

test "namespaces that refer to each other stop at the first repeat" {
    const lua = try api.State.init(a, .{});
    defer lua.deinit();

    try lua.setGlobal("left", Left);
    try lua.doString(
        \\assert(left.name == "left" and left.right.name == "right")
        \\assert(left.right.left == nil)
    , .{});
}

test "a Zig file converts to a Lua module" {
    const lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();

    const Local = struct {
        pub fn triple(x: i64) i64 {
            return x * 3;
        }

        pub const inner = struct {
            pub const depth = 1;
        };
    };
    try lua.setLoadedModule("local", Local);
    try lua.setLoadedModule("item", @import("globals_module_fixture.zig").Item);
    try lua.setLoadedModule("inventory", @import("globals_module_fixture.zig"));
    var item = try lua.newUserdata(@import("globals_module_fixture.zig").Item, .{ .count = 2 }, .{});
    defer item.deinit();
    try lua.setGlobal("item", item);

    try lua.doString(
        \\local inventory = require("inventory")
        \\assert(inventory.name == "inventory" and inventory.std == nil and inventory.label == nil)
        \\assert(inventory.total({ 1, 2, 3 }) == 6)
        \\assert(inventory.Item.add(item, 3) == 5 and item:add(1) == 6)
        \\assert(require("local").triple(2) == 6 and require("local").inner.depth == 1)
        \\assert(require("item").add == inventory.Item.add)
    , .{});
}

test "globals set after a snapshot are gone after reset" {
    const lua = try api.State.init(a, .{});
    defer lua.deinit();

    try lua.setGlobals(.{ .add = add });
    var snapshot = try lua.snapshot(a);
    defer snapshot.deinit();

    try lua.setGlobals(.{ .clamp = clamp, .limit = 3 });
    try lua.doString("assert(clamp(5, 0, 3) == limit)", .{});
    try lua.reset();
    try lua.doString("assert(add(1, 2) == 3 and clamp == nil and limit == nil)", .{});

    try lua.setGlobals(.{ .clamp = clamp });
    try lua.doString("assert(clamp(5, 0, 3) == 3)", .{});
}

test "setGlobals fails when memory runs out and leaves the state usable" {
    const lua = try api.State.init(a, .{ .limits = .{ .max_memory = 512 * 1024 } });
    defer lua.deinit();

    const big: [100_000]i64 = @splat(7);
    if (lua.setGlobals(.{ .add = add, .big = big })) |_| return error.TestExpectedError else |_| {}
    try lua.setGlobals(.{ .add = add });
    try lua.doString("assert(add(1, 1) == 2)", .{});
}
